const { expect } = require("chai");
const { ethers } = require("hardhat");
import * as Contracts from "../typechain-types";
import { BigNumberish, ContractTransaction, Signer } from "ethers";

describe("RockOnyxUSDTVault", function () {
  let RockOnyxUSDTVault;
  let rockOnyxUSDTVault: Contracts.RockOnyxUSDTVault;
  const usdcAddress = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831";
  const usdceAddress = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8";
  const wstethAddress = "0x5979D7b546E38E414F7E9822514be443A4800529";
  const wethAddress = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
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

  let owner: Signer,
    user1: Signer,
    user2: Signer,
    user3: Signer,
    user4: Signer,
    user5: Signer;

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
  async function deposit(sender: Signer, amount: BigNumberish) {
    const userAddress = await sender.getAddress();
    console.log(
      `Depositing ${ethers.formatUnits(amount, 6)} USDC for ${userAddress}`
    );
    await usdc
      .connect(sender)
      .approve(await rockOnyxUSDTVault.getAddress(), amount);
    console.log("approved");
    await rockOnyxUSDTVault.connect(sender).deposit(amount);
  }

  // Helper function for withdrawal
  async function withdraw(user: Signer, shares: BigNumberish) {
    const userAddress = await user.getAddress();
    console.log(
      `Withdrawing ${ethers.formatUnits(shares, 6)} USDC for ${userAddress}`
    );
    await rockOnyxUSDTVault.connect(user).initiateWithdraw(shares);
  }

  async function transferIERC20FundForUser(
    asset: Contracts.IERC20,
    from: string,
    to: Signer,
    amount: number
  ) {
    const impersonatedSigner = await ethers.getImpersonatedSigner(from);
    const recipientAddress = await to.getAddress();

    console.log(
      "balance of impersonatedSigner",
      await asset
        .connect(impersonatedSigner)
        .balanceOf(await impersonatedSigner.getAddress())
    );

    const transferTx = await asset
      .connect(impersonatedSigner)
      .transfer(recipientAddress, ethers.parseUnits(amount.toString(), 6));
    await transferTx.wait();

    const balanceOfUser = await asset.connect(to).balanceOf(optionsReceiver);
    console.log("Balance of user %s", balanceOfUser);
  }

  async function logBalances() {
    const pricePerShare = await rockOnyxUSDTVault.pricePerShare();
    const totalSupply = await rockOnyxUSDTVault.totalAssets();
    console.log(
      "Price/Share %s, totalAssets= %s",
      ethers.formatUnits(pricePerShare.toString(), 6),
      ethers.formatUnits(totalSupply, 6)
    );
  }

  beforeEach(async function () {
    usdc = await ethers.getContractAt("IERC20", usdcAddress);
    usdce = await ethers.getContractAt("IERC20", usdceAddress);

    RockOnyxUSDTVault = await ethers.getContractFactory("RockOnyxUSDTVault");
    [owner, user1, user2, user3, user4, user5] = await ethers.getSigners();

    await deployLiquidityContract();
    await deployCamelotSwapContract();
    await deployAevoContract();

    rockOnyxUSDTVault = await RockOnyxUSDTVault.deploy(
      usdcAddress,
      camelotLiquidityAddress,
      camelotSwapAddress,
      aevoProxyAddress,
      await user1.getAddress(),
      usdceAddress,
      "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", // mock data to test options strategy
      usdcAddress,
      wethAddress,
      wstethAddress
    );

    // transfer fund for user
    optionsReceiver = await user1.getAddress();

    await transferIERC20FundForUser(
      usdc,
      "0x1f7bc4da1a0c2e49d7ef542f74cd46a3fe592cb1",
      user1,
      5000
    );
    await transferIERC20FundForUser(
      usdc,
      "0x1f7bc4da1a0c2e49d7ef542f74cd46a3fe592cb1",
      user2,
      5000
    );
    await transferIERC20FundForUser(
      usdc,
      "0x1f7bc4da1a0c2e49d7ef542f74cd46a3fe592cb1",
      user3,
      5000
    );
    await transferIERC20FundForUser(
      usdc,
      "0x1f7bc4da1a0c2e49d7ef542f74cd46a3fe592cb1",
      user4,
      5000
    );
    await transferIERC20FundForUser(
      usdc,
      "0x1f7bc4da1a0c2e49d7ef542f74cd46a3fe592cb1",
      user5,
      5000
    );
  });

  it.skip("Deposit USDT to vault", async function () {
    // User1 deposits 1000
    await deposit(user1, ethers.parseUnits("1000", 6));

    const totalBalance = await rockOnyxUSDTVault.balanceOf(
      await user1.getAddress()
    );
    console.log(
      "Number of shares of %s after deposit %s",
      await owner.getAddress(),
      ethers.formatEther(totalBalance)
    );

    // rebalance portfolio
    const depositAmount = ethers.parseUnits("100", 6);
    await rockOnyxUSDTVault.connect(owner).allocateAssets();

    console.log(`Depositing ${depositAmount} USDC options`);
    await rockOnyxUSDTVault.connect(owner).depositToVendor(depositAmount, {
      value: ethers.parseEther("0.001753"),
    });
  });

  it.skip("should handle deposits correctly", async function () {
    console.log("Testing deposit functionality...");

    // User1 deposits 1000
    await deposit(user1, ethers.parseUnits("1000", 6));

    // check price per share
    await logBalances();

    // User2 deposits 500
    await deposit(user2, ethers.parseUnits("1000", 6));

    // check price per share
    await logBalances();

    // Assertions
    const user1Address = user1.getAddress();
    const user2Address = user2.getAddress();
    const totalSupplyAfter = await rockOnyxUSDTVault.totalAssets();
    const user1BalanceAfter = await rockOnyxUSDTVault.balanceOf(user1Address);
    const user2BalanceAfter = await rockOnyxUSDTVault.balanceOf(user2Address);

    expect(totalSupplyAfter).to.equal(ethers.parseUnits("2000", 6));
    expect(user1BalanceAfter).to.equal(ethers.parseUnits("1000", 6));
    expect(user2BalanceAfter).to.equal(ethers.parseUnits("1000", 6));
  });

  it.skip("should handle initiateWithdraw correctly", async function () {
    console.log("Testing withdraw functionality...");

    // User1 deposits 1000
    await deposit(user3, ethers.parseUnits("1000", 6));

    // check price per share
    await logBalances();

    await withdraw(user3, ethers.parseUnits("1000", 6));

    const totalSupplyAfter = await rockOnyxUSDTVault.totalAssets();
    const user1BalanceAfter = await rockOnyxUSDTVault.balanceOf(
      await user3.getAddress()
    );

    expect(totalSupplyAfter).to.equal(ethers.parseUnits("1000", 6));
    expect(user1BalanceAfter).to.equal(ethers.parseUnits("0", 6));
  });

  it.skip("should handle complete withdrawal correctly", async function () {
    console.log("Testing withdraw functionality...");

    // User1 deposits 1000
    await deposit(user3, ethers.parseUnits("1000", 6));

    // check price per share
    await logBalances();

    await withdraw(user3, ethers.parseUnits("1000", 6));

    const user3Address = await user3.getAddress();
    const totalSupplyAfter = await rockOnyxUSDTVault.totalAssets();
    const user1BalanceAfter = await rockOnyxUSDTVault.balanceOf(user3Address);

    expect(totalSupplyAfter).to.equal(ethers.parseUnits("1000", 6));
    expect(user1BalanceAfter).to.equal(ethers.parseUnits("0", 6));

    const balanceOfUser3Before = await usdc
      .connect(user3)
      .balanceOf(user3Address);
    console.log("Balance of user before %s", balanceOfUser3Before);

    await rockOnyxUSDTVault.connect(owner).completeWithdraw(user3Address);

    // check USDC balance of user
    const balanceOfUser3After = await usdc
      .connect(user3)
      .balanceOf(user3Address);
    console.log("Balance of user after %s", balanceOfUser3After);

    expect(balanceOfUser3After).to.equal(ethers.parseUnits("5000", 6));
  });

  it("should handle closeOptionsRound correctly", async function () {
    console.log("Testing withdraw functionality...");

    // User1 deposits 1000
    await deposit(user3, ethers.parseUnits("1000", 6));

    // check price per share
    await logBalances();

    const pps = await rockOnyxUSDTVault.pricePerShare();
    expect(pps).to.equal(ethers.parseUnits("1", 6));

    await rockOnyxUSDTVault
      .connect(owner)
      .closeOptionsRound(ethers.parseUnits("500", 6));

    // await rockOnyxUSDTVault.connect(owner).closeRound();

    // const ppsAfter = await rockOnyxUSDTVault.pricePerShare();
    // console.log("ppsAfter", ppsAfter);
    // expect(ppsAfter).to.equal(ethers.parseUnits("1.5", 6));

    // const totalSupplyAfter = await rockOnyxUSDTVault.totalAssets();
    // const user1BalanceAfter = await rockOnyxUSDTVault.balanceOf(
    //   await user3.getAddress()
    // );

    // expect(totalSupplyAfter).to.equal(ethers.parseUnits("1000", 6));
    // expect(user1BalanceAfter).to.equal(ethers.parseUnits("0", 6));
  });
});
