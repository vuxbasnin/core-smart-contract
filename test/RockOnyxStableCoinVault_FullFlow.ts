const { expect } = require("chai");
const { ethers, network } = require("hardhat");
import * as Contracts from "../typechain-types";
import { BigNumberish, ContractTransaction, Signer } from "ethers";
import {
  CHAINID,
  WETH_ADDRESS,
  USDC_ADDRESS,
  USDCE_ADDRESS,
  WSTETH_ADDRESS,
  NonfungiblePositionManager,
  SWAP_ROUTER_ADDRESS,
  AEVO_ADDRESS,
  AEVO_CONNECTOR_ADDRESS,
  USDC_IMPERSONATED_SIGNER_ADDRESS,
  USDCE_IMPERSONATED_SIGNER_ADDRESS,
  WETH_IMPERSONATED_SIGNER_ADDRESS,
  WSTETH_IMPERSONATED_SIGNER_ADDRESS,
} from "../constants";

const chainId: CHAINID = network.config.chainId;

describe("RockOnyxUSDTVault", function () {
  let RockOnyxUSDTVault;
  let rockOnyxUSDTVault: Contracts.RockOnyxUSDTVault;
  const usdcAddress = USDC_ADDRESS[chainId];
  const usdceAddress = USDCE_ADDRESS[chainId];
  console.log("usdceAddress", usdceAddress);
  const wstethAddress = WSTETH_ADDRESS[chainId];
  const wethAddress = WETH_ADDRESS[chainId];
  let usdc: Contracts.IERC20;
  let usdce: Contracts.IERC20;
  let weth: Contracts.IERC20;
  let wsteth: Contracts.IERC20;

  // camelot
  const nonfungiblePositionManager = NonfungiblePositionManager[chainId];
  let camelotLiquidityContract: Contracts.CamelotLiquidity;
  let camelotLiquidityAddress: string;

  // swap router
  const swapRouterAddress = SWAP_ROUTER_ADDRESS[chainId];
  let camelotSwapContract: Contracts.CamelotSwap;
  let camelotSwapAddress: string;

  const aevoAddress = AEVO_ADDRESS[chainId];
  const aevoConnectorAddress = AEVO_CONNECTOR_ADDRESS[chainId];
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
      nonfungiblePositionManager
    )) as Contracts.CamelotLiquidity;
    camelotLiquidityAddress = await camelotLiquidityContract.getAddress();

    console.log(
      "Deployed Camelot LP contract at address %s",
      camelotLiquidityAddress
    );
  }

  async function addLiquidityToSwapProxy(
    asset: Contracts.IERC20,
    amount: number,
    impersonatedAddress: string
  ) {
    const impersonatedSigner = await ethers.getImpersonatedSigner(
      impersonatedAddress
    );

    const transferTx = await asset
      .connect(impersonatedSigner)
      .transfer(camelotSwapAddress, ethers.parseUnits(amount.toString(), 6));
    await transferTx.wait();
    console.log(
      "Transfered fund to SwapProxy %s with amount = %s",
      camelotSwapAddress,
      amount
    );
  }

  async function deployCamelotSwapContract() {
    if (chainId == CHAINID.ARBITRUM_MAINNET) {
      console.log("swapRouterAddress = %s", swapRouterAddress);
      const swapRouter = await ethers.getContractAt(
        "ISwapRouter",
        swapRouterAddress
      );

      const factory = await ethers.getContractFactory("CamelotSwap");
      camelotSwapContract = (await factory.deploy(
        swapRouter
      )) as Contracts.CamelotSwap;
      camelotSwapAddress = await camelotSwapContract.getAddress();
      console.log(
        "Deployed Camelot Swap contract at address %s",
        camelotSwapAddress
      );
    } else if (chainId == CHAINID.ETH_SEPOLIA) {
      // On Ethereum testnet, we don't have swapPool then we use the MockSwap instead of
      const factory = await ethers.getContractFactory("RockOnyxSwap");
      camelotSwapContract = (await factory.deploy(
        "0xE592427A0AEce92De3Edee1F18E0157C05861564" // we don't use this then just a mock value
      )) as Contracts.CamelotSwap;
      camelotSwapAddress = await camelotSwapContract.getAddress();

      console.log(
        "Deployed RockOnyxSwap contract at address %s",
        camelotSwapAddress
      );

      await addLiquidityToSwapProxy(
        usdc,
        50000,
        USDC_IMPERSONATED_SIGNER_ADDRESS[chainId] ?? ""
      );

      await addLiquidityToSwapProxy(
        usdce,
        50000,
        USDCE_IMPERSONATED_SIGNER_ADDRESS[chainId] ?? ""
      );

      await addLiquidityToSwapProxy(
        weth,
        500,
        WETH_IMPERSONATED_SIGNER_ADDRESS[chainId] ?? ""
      );

      await addLiquidityToSwapProxy(
        wsteth,
        500,
        WSTETH_IMPERSONATED_SIGNER_ADDRESS[chainId] ?? ""
      );
    }
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
    const totalSupply = await rockOnyxUSDTVault.totalValueLocked();
    console.log(
      "Price/Share %s, totalAssets= %s",
      ethers.formatUnits(pricePerShare.toString(), 6),
      ethers.formatUnits(totalSupply, 6)
    );
  }

  beforeEach(async function () {
    console.log("usdcAddress %s", usdcAddress, chainId);
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
      nonfungiblePositionManager,
      camelotSwapAddress,
      aevoProxyAddress,
      await user1.getAddress(),
      usdceAddress,
      wethAddress,
      wstethAddress
    );

    // transfer fund for user
    optionsReceiver = await user1.getAddress();

    await transferIERC20FundForUser(
      usdc,
      USDC_IMPERSONATED_SIGNER_ADDRESS[chainId] ?? "",
      user1,
      5000
    );
    await transferIERC20FundForUser(
      usdc,
      USDC_IMPERSONATED_SIGNER_ADDRESS[chainId] ?? "",
      user2,
      5000
    );
    await transferIERC20FundForUser(
      usdc,
      USDC_IMPERSONATED_SIGNER_ADDRESS[chainId] ?? "",
      user3,
      5000
    );
    await transferIERC20FundForUser(
      usdc,
      USDC_IMPERSONATED_SIGNER_ADDRESS[chainId] ?? "",
      user4,
      5000
    );
    await transferIERC20FundForUser(
      usdc,
      USDC_IMPERSONATED_SIGNER_ADDRESS[chainId] ?? "",
      user5,
      5000
    );
  });

  it("Deposit USDT to vault", async function () {
    // User1 deposits 1000
    await deposit(user1, ethers.parseUnits("10", 6));

    const totalBalance = await rockOnyxUSDTVault.balanceOf(
      await user1.getAddress()
    );
    console.log(
      "Number of shares of %s after deposit %s",
      await owner.getAddress(),
      ethers.formatUnits(totalBalance, 6)
    );

    // rebalance portfolio
    const depositAmount = ethers.parseUnits("100", 6);

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
    const totalSupplyAfter = await rockOnyxUSDTVault.totalValueLocked();
    const user1BalanceAfter = await rockOnyxUSDTVault.balanceOf(user1Address);
    const user2BalanceAfter = await rockOnyxUSDTVault.balanceOf(user2Address);

    const precision = ethers.parseUnits("2", 6);
    expect(totalSupplyAfter).to.approximately(ethers.parseUnits("2000", 6), precision);
    expect(user1BalanceAfter).to.approximately(ethers.parseUnits("1000", 6), precision);
    expect(user2BalanceAfter).to.approximately(ethers.parseUnits("1000", 6), precision);
  });

  it.skip("should handle initiateWithdraw correctly", async function () {
    console.log("Testing withdraw functionality...");

    // User1 deposits 1000
    await deposit(user3, ethers.parseUnits("1000", 6));

    // check price per share
    await logBalances();

    await withdraw(user3, ethers.parseUnits("1000", 6));

    const totalSupplyAfter = await rockOnyxUSDTVault.totalValueLocked();
    const user1BalanceAfter = await rockOnyxUSDTVault.balanceOf(
      await user3.getAddress()
    );

    const precision = ethers.parseUnits("2", 6);
    expect(totalSupplyAfter).to.approximately(ethers.parseUnits("1000", 6), precision);
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
    const totalSupplyAfter = await rockOnyxUSDTVault.totalValueLocked();
    const user1BalanceAfter = await rockOnyxUSDTVault.balanceOf(user3Address);

    const precision = ethers.parseUnits("2", 6);
    expect(totalSupplyAfter).to.approximately(ethers.parseUnits("1000", 6), precision);
    expect(user1BalanceAfter).to.equal(ethers.parseUnits("0", 6));

    const balanceOfUser3Before = await usdc
      .connect(user3)
      .balanceOf(user3Address);
    console.log("Balance of user before %s", balanceOfUser3Before);

    /// TODO: We need to implement the withdraw fund from partner
    // await rockOnyxUSDTVault.connect(user3).completeWithdraw();

    // // check USDC balance of user
    // const balanceOfUser3After = await usdc
    //   .connect(user3)
    //   .balanceOf(user3Address);
    // console.log("Balance of user after %s", balanceOfUser3After);

    // expect(balanceOfUser3After).to.equal(ethers.parseUnits("5000", 6));
  });

  it.skip("should handle closeOptionsRound correctly", async function () {
    console.log("Testing withdraw functionality...");

    // User1 deposits 1000
    await deposit(user3, ethers.parseUnits("1000", 6));

    // check price per share
    await logBalances();

    const pps = await rockOnyxUSDTVault.pricePerShare();
    expect(pps).to.approximately(ethers.parseUnits("1", 6), ethers.parseUnits("0.1", 6));

    await rockOnyxUSDTVault
      .connect(owner)
      .closeOptionsRound(ethers.parseUnits("500", 6));

    // await rockOnyxUSDTVault.connect(owner).closeRound();

    const ppsAfter = await rockOnyxUSDTVault.pricePerShare();
    console.log("ppsAfter", ppsAfter);
    expect(ppsAfter).to.approximately(ethers.parseUnits("1.5", 6), ethers.parseUnits("0.1", 6));

    const totalSupplyAfter = await rockOnyxUSDTVault.totalValueLocked();
    const user1BalanceAfter = await rockOnyxUSDTVault.balanceOf(
      await user3.getAddress()
    );

    expect(totalSupplyAfter).to.approximately(ethers.parseUnits("1500", 6), ethers.parseUnits("2", 6));
    expect(user1BalanceAfter).to.equal(ethers.parseUnits("1000", 6));
  });
});
