const { expect } = require("chai");
const { ethers } = require("hardhat");
import * as Contracts from "../typechain-types"; // Adjust the path as necessary
import { BigNumberish, ContractTransaction, Signer } from "ethers";

interface MockERC20 extends Contracts.IERC20 {
  mint: (account: string, amount: BigNumberish) => Promise<ContractTransaction>;
}

describe("RockOnyxUSDTVault", function () {
  let RockOnyxUSDTVault;
  let rockOnyxUSDTVault: Contracts.RockOnyxUSDTVault;
  const usdcAddress = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831";
  const usdceAddress = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8";
  let usdc: Contracts.IERC20;
  let usdce: Contracts.IERC20;

  // camelot
  const nonfungiblePositionManager =
    "0x00c7f3082833e796A5b3e4Bd59f6642FF44DCD15";
  const usdcusdcePoolAddressPool = "0xc86Eb7B85807020b4548EE05B54bfC956eEbbfCD";
  let camelotLiquidityContract: Contracts.CamelotLiquidity;
  let camelotLiquidityAddress: string;

  // swap router
  const swapRouterAddress: string =
    "0xE592427A0AEce92De3Edee1F18E0157C05861564";
  let camelotSwapContract: Contracts.CamelotSwap;
  let camelotSwapAddress: string;

  const aevoAddress = "0x80d40e32FAD8bE8da5C6A42B8aF1E181984D137c";
  const aevoConnectorAddress = "0x69Adf49285c25d9f840c577A0e3cb134caF944D3";
  let aevoOptionsContract: Contracts.AevoOptions;
  let aevoProxyAddress: string;
  let optionsReceiver: string;

  let owner: Signer, user: Signer;

  async function deployLiquidityContract() {
    const factory = await ethers.getContractFactory("CamelotLiquidity");
    camelotLiquidityContract = (await factory.deploy(
      nonfungiblePositionManager,
      usdcusdcePoolAddressPool
    )) as Contracts.CamelotLiquidity;
    camelotLiquidityAddress = await camelotLiquidityContract.getAddress();

    console.log(
      "Deployed Camelot LP contract at address %s",
      camelotLiquidityAddress
    );
  }

  async function deployCamelotSwapContract() {
    const swapRouter = await ethers.getContractAt(
      "ISwapRouter",
      swapRouterAddress
    );

    const factory = await ethers.getContractFactory("CamelotSwap");
    camelotSwapContract = (await factory.deploy(
      swapRouter,
      100
    )) as Contracts.CamelotSwap;
    camelotSwapAddress = await camelotSwapContract.getAddress();
    console.log(
      "Deployed Camelot Swap contract at address %s",
      camelotSwapAddress
    );
  }

  async function deployAevoContract() {
    const factory = await ethers.getContractFactory("AevoOptions");
    aevoOptionsContract = (await factory.deploy(
      usdceAddress,
      aevoAddress,
      aevoConnectorAddress
    )) as Contracts.AevoOptions;
    aevoProxyAddress = await aevoOptionsContract.getAddress();
    console.log("Deployed AEVO contract at address %s", aevoProxyAddress);
  }

  // Helper function for deposit
  async function deposit(user: Signer, amount: BigNumberish) {
    const userAddress = await user.getAddress();
    console.log(
      `Depositing ${ethers.formatUnits(amount, 6)} USDC for ${userAddress}`
    );
    await usdc
      .connect(user)
      .approve(await rockOnyxUSDTVault.getAddress(), amount);
    await rockOnyxUSDTVault.connect(user).deposit(amount);
  }

  beforeEach(async function () {
    usdc = await ethers.getContractAt("IERC20", usdcAddress);
    usdce = await ethers.getContractAt("IERC20", usdceAddress);

    RockOnyxUSDTVault = await ethers.getContractFactory("RockOnyxUSDTVault");
    [owner, user] = await ethers.getSigners();

    await deployLiquidityContract();
    await deployCamelotSwapContract();
    await deployAevoContract();

    rockOnyxUSDTVault = await RockOnyxUSDTVault.deploy(
      usdcAddress,
      camelotLiquidityAddress,
      camelotSwapAddress,
      aevoProxyAddress,
      await user.getAddress(),
      usdceAddress,
      "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", // mock data to test options strategy
      "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", // mock data to test options strategy
      "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", // mock data to test options strategy
      "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0" // mock data to test options strategy
    );

    // transfer fund for user
    optionsReceiver = await user.getAddress();
    const impersonatedSigner = await ethers.getImpersonatedSigner(
      "0x1f7bc4da1a0c2e49d7ef542f74cd46a3fe592cb1"
    );
    console.log(
      "balance of impersonatedSigner",
      await usdc
        .connect(impersonatedSigner)
        .balanceOf(await impersonatedSigner.getAddress())
    );

    const transferTx = await usdc
      .connect(impersonatedSigner)
      .transfer(optionsReceiver, ethers.parseUnits("10000", 6));
    await transferTx.wait();

    const balanceOfUser = await usdc.connect(user).balanceOf(optionsReceiver);
    console.log("Balance of user %s", balanceOfUser);
  });

  it("Deposit USDT to vault", async function () {
    // User1 deposits 1000
    await deposit(user, ethers.parseUnits("1000", 6));

    const totalBalance = await rockOnyxUSDTVault.balanceOf(
      await user.getAddress()
    );
    console.log(
      "Number of shares of %s after deposit %s",
      await owner.getAddress(),
      ethers.formatEther(totalBalance)
    );

    // rebalance portfolio
    const depositAmount = ethers.parseUnits("100", 6);
    await rockOnyxUSDTVault.connect(owner).rebalance();

    console.log(
      `Depositing ${depositAmount} USDC options`
    );
    await rockOnyxUSDTVault.connect(owner).depositToVendor(depositAmount, {
      value: ethers.parseEther("0.001753"),
    });
  });
});
