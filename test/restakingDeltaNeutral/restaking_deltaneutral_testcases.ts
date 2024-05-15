const { ethers, network } = require("hardhat");
import { expect } from "chai";

import * as Contracts from "../../typechain-types";
import {
  CHAINID,
  WETH_ADDRESS,
  USDC_ADDRESS,
  UNISWAP_ROUTER_ADDRESS,
  AEVO_ADDRESS,
  AEVO_CONNECTOR_ADDRESS,
  USDC_IMPERSONATED_SIGNER_ADDRESS,
  ETH_PRICE_FEED_ADDRESS,
  EZTETH_ETH_PRICE_FEED_ADDRESS,
  EZETH_ADDRESS,
  ZIRCUIT_DEPOSIT_ADDRESS,
  RENZO_DEPOSIT_ADDRESS,
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

  let renzoRestakingDNVault: Contracts.RenzoRestakingDeltaNeutralVault;
  let usdc: Contracts.IERC20;

  const usdcImpersonatedSigner = USDC_IMPERSONATED_SIGNER_ADDRESS[chainId];
  const usdcAddress = USDC_ADDRESS[chainId] || "";
  const wethAddress = WETH_ADDRESS[chainId] || "";
  const ezEthAddress = EZETH_ADDRESS[chainId] || "";
  const swapRouterAddress = UNISWAP_ROUTER_ADDRESS[chainId];
  const aevoAddress = AEVO_ADDRESS[chainId];
  const aevoConnectorAddress = AEVO_CONNECTOR_ADDRESS[chainId];
  const ethPriceFeed = ETH_PRICE_FEED_ADDRESS[chainId];
  const ezEth_EthPriceFeed = EZTETH_ETH_PRICE_FEED_ADDRESS[chainId];
  const renzoDepositAddress = RENZO_DEPOSIT_ADDRESS[chainId];
  const zircuitDepositAddress = ZIRCUIT_DEPOSIT_ADDRESS[chainId];

  let priceConsumerContract: Contracts.PriceConsumer;
  let uniSwapContract: Contracts.UniSwap;

  async function deployPriceConsumerContract() {
    const factory = await ethers.getContractFactory("PriceConsumer");
    console.log("wethAddress %s usdcAddress %s ethPriceFeed %s", wethAddress, usdcAddress, ethPriceFeed);
    console.log("ezEthAddress %s wethAddress %s ezEth_EthPriceFeed %s", ezEthAddress, wethAddress, ezEth_EthPriceFeed);

    priceConsumerContract = await factory.deploy(
      [wethAddress, ezEthAddress],
      [usdcAddress, wethAddress],
      [ethPriceFeed, ezEth_EthPriceFeed]
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

  async function deployRenzoRestakingDeltaNeutralVault() {
    const renzoRestakingDeltaNeutralVault = await ethers.getContractFactory(
      "RenzoRestakingDeltaNeutralVault"
    );

    renzoRestakingDNVault = await renzoRestakingDeltaNeutralVault.deploy(
      usdcAddress,
      wethAddress,
      await uniSwapContract.getAddress(),
      aevoAddress,
      aevoRecipientAddress,
      aevoConnectorAddress,
      ezEthAddress,
      BigInt(1 * 1e6),
      [renzoDepositAddress, zircuitDepositAddress]
    );
    await renzoRestakingDNVault.waitForDeployment();

    console.log(
      "deploy rockOnyxDeltaNeutralVaultContract successfully: %s",
      await renzoRestakingDNVault.getAddress()
    );
  }

  beforeEach(async function () {
    [admin, user1, user2, user3, user4] = await ethers.getSigners();
    aevoRecipientAddress = await user4.getAddress();
    usdc = await ethers.getContractAt("IERC20", usdcAddress);
    
    await deployPriceConsumerContract();
    await deployUniSwapContract();
    await deployRenzoRestakingDeltaNeutralVault();
    console.log("deployRenzoRestakingDeltaNeutralVault");
  });

  async function deposit(sender: Signer, amount: BigNumberish) {
    await usdc
      .connect(sender)
      .approve(await renzoRestakingDNVault.getAddress(), amount);

    await renzoRestakingDNVault.connect(sender).deposit(amount);
  }

  async function transferUsdcForUser(from: Signer, to: Signer, amount: number) {
    const transferTx = await usdc.connect(from).transfer(to, amount);
    await transferTx.wait();
  }

  async function logAndReturnTotalValueLock() {
    const totalValueLocked = await renzoRestakingDNVault
      .connect(admin)
      .totalValueLocked();

    console.log("totalValueLocked %s", totalValueLocked);

    return totalValueLocked;
  }

  it("seed data", async function () {
    const usdcSigner = await ethers.getImpersonatedSigner(usdcImpersonatedSigner);

    await transferUsdcForUser(usdcSigner, user1, 100000 * 1e6);
    await transferUsdcForUser(usdcSigner, user2, 100000 * 1e6);
    await transferUsdcForUser(usdcSigner, user3, 100000 * 1e6);
    await transferUsdcForUser(usdcSigner, user4, 100000 * 1e6);
    await transferUsdcForUser(usdcSigner, admin, 100000 * 1e6);
  });

  it("user deposit -> withdraw", async function () {
    console.log(
      "-------------deposit to restakingDeltaNeutralVault---------------"
    );
    await deposit(user1, 10 * 1e6);
    await deposit(user2, 100 * 1e6);

    let totalValueLock = await logAndReturnTotalValueLock();
    expect(totalValueLock).to.approximately(110 * 1e6, PRECISION);

    console.log("-------------Users initial withdrawals---------------");
    const initiateWithdrawalTx1 = await renzoRestakingDNVault
      .connect(user2)
      .initiateWithdrawal(100 * 1e6);
    await initiateWithdrawalTx1.wait();

    console.log("-------------handleWithdrawalFunds---------------");
    const handleWithdrawalFundsTx = await renzoRestakingDNVault
      .connect(admin)
      .acquireWithdrawalFunds(100 * 1e6);
    await handleWithdrawalFundsTx.wait();

    console.log("-------------complete withdrawals---------------");
    let user2Balance = await usdc.connect(user2).balanceOf(user2);
    console.log("usdc of user before withdraw %s", user2Balance);

    const completeWithdrawalTx = await renzoRestakingDNVault
      .connect(user2)
      .completeWithdrawal(100 * 1e6);
    await completeWithdrawalTx.wait();

    let user1BalanceAfterWithdraw = await usdc.connect(user2).balanceOf(user2);
    console.log("usdc of user after withdraw %s", user1BalanceAfterWithdraw);
    expect(user1BalanceAfterWithdraw).to.approximately(user2Balance + BigInt(95 * 1e6),PRECISION);
  });

  it("user deposit -> deposit to perp dex -> deposit to renzo -> deposit to zircuit", async function () {
    console.log(
      "-------------deposit to restakingDeltaNeutralVault---------------"
    );
    await deposit(user1, 10 * 1e6);
    await deposit(user2, 100 * 1e6);

    let totalValueLock = await logAndReturnTotalValueLock();
    expect(totalValueLock).to.approximately(110 * 1e6, PRECISION);

    console.log("-------------deposit to vendor on aevo---------------");
    if(chainId == CHAINID.ETH_MAINNET){
      await renzoRestakingDNVault.connect(admin).depositToVendor(500000);
      totalValueLock = await logAndReturnTotalValueLock();
    }else{
      await renzoRestakingDNVault.connect(admin).depositToVendorL2(650000, {
        value: ethers.parseEther("0.000159539385325246"),
      });
    }
    expect(totalValueLock).to.approximately(110 * 1e6, PRECISION);

    console.log("-------------open position---------------");
    const openPositionTx = await renzoRestakingDNVault
      .connect(admin)
      .openPosition(BigInt(0.01 * 1e18));
    await openPositionTx.wait();
  });

  it("user deposit -> deposit to perp dex -> open position -> close position -> sync restaking balance -> withdraw", async function () {
    console.log(
      "-------------deposit to restakingDeltaNeutralVault---------------"
    );
    await deposit(user1, 100 * 1e6);
    await deposit(user2, 200 * 1e6);

    let totalValueLock = await logAndReturnTotalValueLock();
    expect(totalValueLock).to.approximately(300 * 1e6, PRECISION);

    console.log("-------------deposit to vendor on aevo---------------");
    if(chainId == CHAINID.ETH_MAINNET){
      await renzoRestakingDNVault.connect(admin).depositToVendor(500000);
      totalValueLock = await logAndReturnTotalValueLock();
    }else{
      await renzoRestakingDNVault.connect(admin).depositToVendorL2(650000, {
        value: ethers.parseEther("0.000159539385325246"),
      });
    }
    expect(totalValueLock).to.approximately(300 * 1e6, PRECISION);

    console.log("-------------open position---------------");
    const openPositionTx = await renzoRestakingDNVault
      .connect(admin)
      .openPosition(BigInt(0.02 * 1e18));
    await openPositionTx.wait();

    console.log("-------------sync restaking balance---------------");
    const syncBalanceTx = await renzoRestakingDNVault
      .connect(admin)
      .syncBalance(150*1e6);
    await syncBalanceTx.wait();

    console.log("-------------close position---------------");
    const closePositionTx = await renzoRestakingDNVault
      .connect(admin)
      .closePosition(BigInt(0.01 * 1e18));
    await closePositionTx.wait();

    console.log("-------------Users initial withdrawals---------------");
    const initiateWithdrawalTx1 = await renzoRestakingDNVault
      .connect(user2)
      .initiateWithdrawal(100 * 1e6);
    await initiateWithdrawalTx1.wait();

    await usdc.connect(admin).approve(await renzoRestakingDNVault.getAddress(), 50 * 1e6);
    const handlePostWithdrawTx = await renzoRestakingDNVault
      .connect(admin)
      .handlePostWithdrawFromVendor(50*1e6);
    await handlePostWithdrawTx.wait();
    
    console.log("-------------handleWithdrawalFunds---------------");
    const handleWithdrawalFundsTx = await renzoRestakingDNVault
      .connect(admin)
      .acquireWithdrawalFunds(100*1e6);
    await initiateWithdrawalTx1.wait();

    console.log("-------------complete withdrawals---------------");
    let user2Balance = await usdc.connect(user2).balanceOf(user2);
    console.log("usdc of user before withdraw %s", user2Balance);

    const completeWithdrawalTx = await renzoRestakingDNVault
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

  it("user deposit -> deposit to perp dex -> withdraw", async function () {
    console.log("-------------deposit to restakingDeltaNeutralVault---------------"
    );
    await deposit(user1, 100 * 1e6);
    await deposit(user2, 200 * 1e6);

    let totalValueLock = await logAndReturnTotalValueLock();
    expect(totalValueLock).to.approximately(300 * 1e6, PRECISION);

    console.log("-------------deposit to vendor on aevo---------------");
    if(chainId == CHAINID.ETH_MAINNET){
      await renzoRestakingDNVault.connect(admin).depositToVendor(500000);
      totalValueLock = await logAndReturnTotalValueLock();
    }else{
      await renzoRestakingDNVault.connect(admin).depositToVendorL2(650000, {
        value: ethers.parseEther("0.000159539385325246"),
      });
    }
    expect(totalValueLock).to.approximately(300 * 1e6, PRECISION);

    console.log("-------------Users initial withdrawals---------------");
    const initiateWithdrawalTx1 = await renzoRestakingDNVault
      .connect(user2)
      .initiateWithdrawal(100 * 1e6);
    await initiateWithdrawalTx1.wait();

    await usdc.connect(admin).approve(await renzoRestakingDNVault.getAddress(), 50 * 1e6);
    const handlePostWithdrawTx = await renzoRestakingDNVault
      .connect(admin)
      .handlePostWithdrawFromVendor(50*1e6);
    await handlePostWithdrawTx.wait();

    console.log("-------------handleWithdrawalFunds---------------");
    const handleWithdrawalFundsTx = await renzoRestakingDNVault
      .connect(admin)
      .acquireWithdrawalFunds(100*1e6);
    await initiateWithdrawalTx1.wait();

    console.log("-------------complete withdrawals---------------");
    let user2Balance = await usdc.connect(user2).balanceOf(user2);
    console.log("usdc of user before withdraw %s", user2Balance);

    const completeWithdrawalTx = await renzoRestakingDNVault
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