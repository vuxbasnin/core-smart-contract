const { ethers, network } = require("hardhat");
import { expect } from "chai";

import * as Contracts from "../../typechain-types";
import {
  CHAINID,
  WETH_ADDRESS,
  USDC_ADDRESS,
  USDT_ADDRESS,
  DAI_ADDRESS,
  UNISWAP_ROUTER_ADDRESS,
  AEVO_ADDRESS,
  AEVO_CONNECTOR_ADDRESS,
  USDC_IMPERSONATED_SIGNER_ADDRESS,
  USDT_IMPERSONATED_SIGNER_ADDRESS,
  DAI_IMPERSONATED_SIGNER_ADDRESS,
  ETH_PRICE_FEED_ADDRESS,
  USDT_PRICE_FEED_ADDRESS,
  DAI_PRICE_FEED_ADDRESS,
  RSETH_ETH_PRICE_FEED_ADDRESS,
  RSETH_ADDRESS,
  ZIRCUIT_DEPOSIT_ADDRESS,
  KELP_DEPOSIT_ADDRESS,
} from "../../constants";
import { BigNumberish, Signer } from "ethers";

const chainId: CHAINID = network.config.chainId;
console.log("chainId ",chainId);
let aevoRecipientAddress : string;

const PRECISION = 2 * 1e6;

describe("RockOnyxDeltaNeutralVault", function () {
  let admin: Signer,
    user1: Signer,
    user2: Signer,
    user3: Signer,
    user4: Signer;

  let kelpRestakingDNVault: Contracts.KelpRestakingDeltaNeutralVault;
  let usdc: Contracts.IERC20;
  let usdt: Contracts.IERC20;
  let dai: Contracts.IERC20;

  const usdcImpersonatedSigner = USDC_IMPERSONATED_SIGNER_ADDRESS[chainId];
  const usdtImpersonatedSigner = USDT_IMPERSONATED_SIGNER_ADDRESS[chainId];
  const daiImpersonatedSigner = DAI_IMPERSONATED_SIGNER_ADDRESS[chainId];
  const usdcAddress = USDC_ADDRESS[chainId] || "";
  const usdtAddress = USDT_ADDRESS[chainId] || "";
  const daiAddress = DAI_ADDRESS[chainId] || "";
  const wethAddress = WETH_ADDRESS[chainId] || "";
  const rsEthAddress = RSETH_ADDRESS[chainId] || "";
  const swapRouterAddress = UNISWAP_ROUTER_ADDRESS[chainId];
  const aevoAddress = AEVO_ADDRESS[chainId];
  const aevoConnectorAddress = AEVO_CONNECTOR_ADDRESS[chainId];
  const ethPriceFeed = ETH_PRICE_FEED_ADDRESS[chainId];
  const rsEth_EthPriceFeed = RSETH_ETH_PRICE_FEED_ADDRESS[chainId];
  const usdtPriceFeed = USDT_PRICE_FEED_ADDRESS[chainId];
  const daiPriceFeed = DAI_PRICE_FEED_ADDRESS[chainId];
  const kelpDepositAddress = KELP_DEPOSIT_ADDRESS[chainId];
  const zircuitDepositAddress = ZIRCUIT_DEPOSIT_ADDRESS[chainId];

  let priceConsumerContract: Contracts.PriceConsumer;
  let uniSwapContract: Contracts.UniSwap;

  async function deployPriceConsumerContract() {
    const factory = await ethers.getContractFactory("PriceConsumer");

    priceConsumerContract = await factory.deploy(
      [wethAddress, rsEthAddress, usdtAddress , daiAddress],
      [usdcAddress, wethAddress, usdcAddress, usdtAddress],
      [ethPriceFeed, rsEth_EthPriceFeed, usdtPriceFeed, daiPriceFeed]
    );
    await priceConsumerContract.waitForDeployment();

    console.log(
      "Deployed price consumer contract at address %s",
      await priceConsumerContract.getAddress()
    );
  }

  async function deployUniSwapContract() {
    const factory = await ethers.getContractFactory("UniSwap");
    uniSwapContract = await factory.deploy(
      swapRouterAddress,
      priceConsumerContract.getAddress()
    );
    await uniSwapContract.waitForDeployment();

    console.log(
      "Deployed uni swap contract at address %s",
      await uniSwapContract.getAddress()
    );
  }

  async function deployKelpRestakingDeltaNeutralVault() {
    const kelpRestakingDeltaNeutralVault = await ethers.getContractFactory(
      "KelpRestakingDeltaNeutralVault"
    );

    kelpRestakingDNVault = await kelpRestakingDeltaNeutralVault.deploy(
      usdcAddress,
      wethAddress,
      aevoAddress,
      aevoRecipientAddress,
      aevoConnectorAddress,
      rsEthAddress,
      BigInt(1 * 1e6),
      [kelpDepositAddress, zircuitDepositAddress],
      await uniSwapContract.getAddress(),
      [usdcAddress, rsEthAddress, usdtAddress, daiAddress],
      [wethAddress, wethAddress, usdcAddress, usdtAddress],
      [500, 100, 100, 100]
    );
    await kelpRestakingDNVault.waitForDeployment();

    console.log(
      "deploy rockOnyxDeltaNeutralVaultContract successfully: %s",
      await kelpRestakingDNVault.getAddress()
    );
  }

  beforeEach(async function () {
    [admin, user1, user2, user3, user4] = await ethers.getSigners();
    aevoRecipientAddress = await user4.getAddress();
    usdc = await ethers.getContractAt("IERC20", usdcAddress);
    usdt = await ethers.getContractAt("IERC20", usdtAddress);
    dai = await ethers.getContractAt("IERC20", daiAddress);

    await deployPriceConsumerContract();
    await deployUniSwapContract();
    await deployKelpRestakingDeltaNeutralVault();
    console.log("deployKelpRestakingDeltaNeutralVault");
  });

  async function deposit(sender: Signer, amount: BigNumberish, token: Contracts.IERC20, tokenTransit: Contracts.IERC20) {
    await token
      .connect(sender)
      .approve(await kelpRestakingDNVault.getAddress(), amount);

    await kelpRestakingDNVault.connect(sender).deposit(amount, token, tokenTransit);
  }

  async function transferForUser(token: Contracts.IERC20, from: Signer, to: Signer, amount: BigNumberish) {
    const transferTx = await token.connect(from).transfer(to, amount);
    await transferTx.wait();
  }

  async function logAndReturnTotalValueLock() {
    const totalValueLocked = await kelpRestakingDNVault
      .connect(admin)
      .totalValueLocked();

    console.log("totalValueLocked %s", totalValueLocked);

    return totalValueLocked;
  }

  it("seed data", async function () {
    const usdcSigner = await ethers.getImpersonatedSigner(usdcImpersonatedSigner);
    const usdtSigner = await ethers.getImpersonatedSigner(usdtImpersonatedSigner);
    const daiSigner = await ethers.getImpersonatedSigner(daiImpersonatedSigner);

    await transferForUser(usdc, usdcSigner, user1, 100000 * 1e6);
    await transferForUser(usdc, usdcSigner, user2, 100000 * 1e6);
    await transferForUser(usdc, usdcSigner, user3, 100000 * 1e6);
    await transferForUser(usdc, usdcSigner, user4, 100000 * 1e6);
    await transferForUser(usdc, usdcSigner, admin, 100000 * 1e6);

    await transferForUser(usdt, usdtSigner, user2, 100000 * 1e6);
    await transferForUser(dai, daiSigner, user2, BigInt(100000 * 1e18));
  });

  it("user deposit -> withdraw", async function () {
    console.log(
      "-------------deposit to restakingDeltaNeutralVault---------------"
    );
    await deposit(user1, 10 * 1e6, usdc, usdc);
    await deposit(user2, 50 * 1e6, usdt, usdt);
    await deposit(user2, BigInt(50 * 1e18), dai, usdt);

    let totalValueLock = await logAndReturnTotalValueLock();
    expect(totalValueLock).to.approximately(110 * 1e6, PRECISION);

    console.log("-------------Users initial withdrawals---------------");
    const initiateWithdrawalTx1 = await kelpRestakingDNVault
      .connect(user2)
      .initiateWithdrawal(99.9 * 1e6);
    await initiateWithdrawalTx1.wait();

    console.log("-------------handleWithdrawalFunds---------------");
    const handleWithdrawalFundsTx = await kelpRestakingDNVault
      .connect(admin)
      .acquireWithdrawalFunds(99.9 * 1e6);
    await handleWithdrawalFundsTx.wait();

    console.log("-------------complete withdrawals---------------");
    let user2Balance = await usdc.connect(user2).balanceOf(user2);
    console.log("usdc of user before withdraw %s", user2Balance);

    const completeWithdrawalTx = await kelpRestakingDNVault
      .connect(user2)
      .completeWithdrawal(99.9 * 1e6);
    await completeWithdrawalTx.wait();

    let user1BalanceAfterWithdraw = await usdc.connect(user2).balanceOf(user2);
    console.log("usdc of user after withdraw %s", user1BalanceAfterWithdraw);
    expect(user1BalanceAfterWithdraw).to.approximately(user2Balance + BigInt(95 * 1e6),PRECISION);
  });

  it.skip("user deposit -> deposit to perp dex -> deposit to kelp -> deposit to zircuit", async function () {
    console.log(
      "-------------deposit to restakingDeltaNeutralVault---------------"
    );
    await deposit(user1, 10 * 1e6, usdc, usdc);
    await deposit(user2, 100 * 1e6, usdc, usdc);

    let totalValueLock = await logAndReturnTotalValueLock();
    expect(totalValueLock).to.approximately(110 * 1e6, PRECISION);

    console.log("-------------deposit to vendor on aevo---------------");
    if(chainId == CHAINID.ETH_MAINNET){
      await kelpRestakingDNVault.connect(admin).depositToVendor(500000);
      totalValueLock = await logAndReturnTotalValueLock();
    }else{
      await kelpRestakingDNVault.connect(admin).depositToVendorL2(650000, {
        value: ethers.parseEther("0.000159539385325246"),
      });
    }
    expect(totalValueLock).to.approximately(110 * 1e6, PRECISION);

    console.log("-------------open position---------------");
    const openPositionTx = await kelpRestakingDNVault
      .connect(admin)
      .openPosition(BigInt(0.01 * 1e18));
    await openPositionTx.wait();
  });

  it.skip("user deposit -> deposit to perp dex -> open position -> close position -> sync restaking balance -> withdraw", async function () {
    console.log(
      "-------------deposit to restakingDeltaNeutralVault---------------"
    );
    await deposit(user1, 100 * 1e6, usdc, usdc);
    await deposit(user2, 200 * 1e6, usdc, usdc);

    let totalValueLock = await logAndReturnTotalValueLock();
    expect(totalValueLock).to.approximately(300 * 1e6, PRECISION);

    console.log("-------------deposit to vendor on aevo---------------");
    if(chainId == CHAINID.ETH_MAINNET){
      await kelpRestakingDNVault.connect(admin).depositToVendor(500000);
      totalValueLock = await logAndReturnTotalValueLock();
    }else{
      await kelpRestakingDNVault.connect(admin).depositToVendorL2(650000, {
        value: ethers.parseEther("0.000159539385325246"),
      });
    }
    expect(totalValueLock).to.approximately(300 * 1e6, PRECISION);

    console.log("-------------open position---------------");
    const openPositionTx = await kelpRestakingDNVault
      .connect(admin)
      .openPosition(BigInt(0.02 * 1e18));
    await openPositionTx.wait();

    console.log("-------------sync restaking balance---------------");
    const syncBalanceTx = await kelpRestakingDNVault
      .connect(admin)
      .syncBalance(150*1e6);
    await syncBalanceTx.wait();

    console.log("-------------close position---------------");
    const closePositionTx = await kelpRestakingDNVault
      .connect(admin)
      .closePosition(BigInt(0.01 * 1e18));
    await closePositionTx.wait();

    console.log("-------------Users initial withdrawals---------------");
    const initiateWithdrawalTx1 = await kelpRestakingDNVault
      .connect(user2)
      .initiateWithdrawal(100 * 1e6);
    await initiateWithdrawalTx1.wait();

    await usdc.connect(admin).approve(await kelpRestakingDNVault.getAddress(), 50 * 1e6);
    const handlePostWithdrawTx = await kelpRestakingDNVault
      .connect(admin)
      .handlePostWithdrawFromVendor(50*1e6);
    await handlePostWithdrawTx.wait();
    
    console.log("-------------handleWithdrawalFunds---------------");
    const handleWithdrawalFundsTx = await kelpRestakingDNVault
      .connect(admin)
      .acquireWithdrawalFunds(100*1e6);
    await initiateWithdrawalTx1.wait();

    console.log("-------------complete withdrawals---------------");
    let user2Balance = await usdc.connect(user2).balanceOf(user2);
    console.log("usdc of user before withdraw %s", user2Balance);

    const completeWithdrawalTx = await kelpRestakingDNVault
      .connect(user2)
      .completeWithdrawal(100 * 1e6);
    await completeWithdrawalTx.wait();

    let user1BalanceAfterWithdraw = await usdc.connect(user2).balanceOf(user2);
    console.log("usdc of user after withdraw %s", user1BalanceAfterWithdraw);
    expect(user1BalanceAfterWithdraw).to.approximately(
      user2Balance + BigInt(95 * 1e6),
      PRECISION
    );
  });

  it.skip("user deposit -> deposit to perp dex -> withdraw", async function () {
    console.log("-------------deposit to restakingDeltaNeutralVault---------------"
    );
    await deposit(user1, 100 * 1e6, usdc, usdc);
    await deposit(user2, 200 * 1e6, usdc, usdc);

    let totalValueLock = await logAndReturnTotalValueLock();
    expect(totalValueLock).to.approximately(300 * 1e6, PRECISION);

    console.log("-------------deposit to vendor on aevo---------------");
    if(chainId == CHAINID.ETH_MAINNET){
      await kelpRestakingDNVault.connect(admin).depositToVendor(500000);
      totalValueLock = await logAndReturnTotalValueLock();
    }else{
      await kelpRestakingDNVault.connect(admin).depositToVendorL2(650000, {
        value: ethers.parseEther("0.000159539385325246"),
      });
    }
    expect(totalValueLock).to.approximately(300 * 1e6, PRECISION);

    console.log("-------------Users initial withdrawals---------------");
    const initiateWithdrawalTx1 = await kelpRestakingDNVault
      .connect(user2)
      .initiateWithdrawal(100 * 1e6);
    await initiateWithdrawalTx1.wait();

    await usdc.connect(admin).approve(await kelpRestakingDNVault.getAddress(), 50 * 1e6);
    const handlePostWithdrawTx = await kelpRestakingDNVault
      .connect(admin)
      .handlePostWithdrawFromVendor(50*1e6);
    await handlePostWithdrawTx.wait();

    console.log("-------------handleWithdrawalFunds---------------");
    const handleWithdrawalFundsTx = await kelpRestakingDNVault
      .connect(admin)
      .acquireWithdrawalFunds(100*1e6);
    await initiateWithdrawalTx1.wait();

    console.log("-------------complete withdrawals---------------");
    let user2Balance = await usdc.connect(user2).balanceOf(user2);
    console.log("usdc of user before withdraw %s", user2Balance);

    const completeWithdrawalTx = await kelpRestakingDNVault
      .connect(user2)
      .completeWithdrawal(100 * 1e6);
    await completeWithdrawalTx.wait();

    let user1BalanceAfterWithdraw = await usdc.connect(user2).balanceOf(user2);
    console.log("usdc of user after withdraw %s", user1BalanceAfterWithdraw);
    expect(user1BalanceAfterWithdraw).to.approximately(user2Balance + BigInt(95 * 1e6), PRECISION);
    totalValueLock = await logAndReturnTotalValueLock();
    expect(totalValueLock).to.approximately(200 * 1e6, PRECISION);
  });
});