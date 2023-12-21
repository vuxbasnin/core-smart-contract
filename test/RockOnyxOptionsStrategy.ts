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
  let usdcAddress: string;
  let mockUSDC: MockERC20;
  let camelotLiquidityContract: Contracts.CamelotLiquidity;
  let camelotLiquidityAddress: string;
  let camelotSwapContract: Contracts.CamelotSwap;
  let camelotSwapAddress: string;

  let aevoOptionsContract: Contracts.AevoOptions;
  let aevoProxyAddress: string;

  let mockAEVO: Contracts.MockAEVO;

  let owner: Signer, user: Signer;

  async function deployMockUSDC() {
    // Deploy a mock USDC contract and mint tokens
    const MockUSDC = await ethers.getContractFactory("MockERC20");
    mockUSDC = (await MockUSDC.deploy()) as MockERC20;
    usdcAddress = await mockUSDC.getAddress();
    console.log("Deployed mUSDC at address %s", usdcAddress);
  }

  async function deployLiquidityContract() {
    const factory = await ethers.getContractFactory("CamelotLiquidity");
    camelotLiquidityContract = (await factory.deploy(
      "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
    )) as Contracts.CamelotLiquidity;
    camelotLiquidityAddress = await camelotLiquidityContract.getAddress();
    console.log(
      "Deployed Camelot LP contract at address %s",
      camelotLiquidityAddress
    );
  }

  async function deployCamelotSwapContract() {
    const mockSwapRouterFactory = await ethers.getContractFactory(
      "MockSwapRouter"
    );
    const swapRouter =
      (await mockSwapRouterFactory.deploy()) as Contracts.MockSwapRouter;

    const factory = await ethers.getContractFactory("CamelotSwap");
    camelotSwapContract = (await factory.deploy(
      swapRouter
    )) as Contracts.CamelotSwap;
    camelotSwapAddress = await camelotSwapContract.getAddress();
    console.log(
      "Deployed Camelot Swap contract at address %s",
      camelotSwapAddress
    );
  }

  async function deployAevoContract() {
    const mockAEVOFactory = await ethers.getContractFactory("MockAEVO");
    mockAEVO = (await mockAEVOFactory.deploy()) as Contracts.MockAEVO;

    const factory = await ethers.getContractFactory("AevoOptions");
    aevoOptionsContract = (await factory.deploy(
      await mockAEVO.getAddress()
    )) as Contracts.AevoOptions;
    aevoProxyAddress = await aevoOptionsContract.getAddress();
    console.log("Deployed AEVO contract at address %s", aevoProxyAddress);
  }

  // Helper function for deposit
  async function deposit(user: Signer, amount: BigNumberish) {
    const userAddress = await user.getAddress();
    console.log(
      `Depositing ${ethers.formatEther(amount)} USDC for ${userAddress}`
    );
    await mockUSDC
      .connect(user)
      .approve(await rockOnyxUSDTVault.getAddress(), amount);
    await rockOnyxUSDTVault.connect(user).deposit(amount);
  }

  beforeEach(async function () {
    RockOnyxUSDTVault = await ethers.getContractFactory("RockOnyxUSDTVault");
    [owner, user] = await ethers.getSigners();

    await deployMockUSDC();
    await deployLiquidityContract();
    await deployCamelotSwapContract();
    await deployAevoContract();

    rockOnyxUSDTVault = await RockOnyxUSDTVault.deploy(
      usdcAddress,
      camelotLiquidityAddress,
      camelotSwapAddress,
      aevoProxyAddress,
      await user.getAddress(),
      "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
      "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
      "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
      "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0"
    );
  });

  it("Deposit USDT to vault", async function () {
    // Mint USDC tokens to user
    await mockUSDC.mint(await owner.getAddress(), ethers.parseEther("10000"));

    // User1 deposits 1000
    await deposit(owner, ethers.parseEther("1000"));

    const totalBalance = await rockOnyxUSDTVault.balanceOf(
      await owner.getAddress()
    );
    console.log(
      "Number of shares of %s after deposit %s",
      await owner.getAddress(),
      ethers.formatEther(totalBalance)
    );

    // rebalance portfolio
    await rockOnyxUSDTVault.connect(owner).rebalance();

    const amount = 200;
    console.log(
      `Depositing ${ethers.parseEther(amount.toString())} USDC options`
    );
    await rockOnyxUSDTVault
      .connect(owner)
      .depositToVendor(ethers.parseEther(amount.toString()));
  });
});
