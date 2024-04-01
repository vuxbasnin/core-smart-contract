const { ethers, network } = require("hardhat");
import { expect } from "chai";
import axios from "axios";

import * as Contracts from "../../typechain-types";
import {
  CHAINID,
  WETH_ADDRESS,
  USDC_ADDRESS,
  WSTETH_ADDRESS,
  SWAP_ROUTER_ADDRESS,
  AEVO_ADDRESS,
  AEVO_CONNECTOR_ADDRESS,
  USDC_IMPERSONATED_SIGNER_ADDRESS,
  USDCE_IMPERSONATED_SIGNER_ADDRESS,
} from "../../constants";
import {
  Signer,
  BigNumberish,
  ContractTransaction,
  AbiCoder,
  ContractTransactionReceipt,
  ethers,
  BigNumberish,
} from "ethers";
import { float } from "hardhat/internal/core/params/argumentTypes";

// const chainId: CHAINID = network.config.chainId;
const chainId: CHAINID = 42161;
const PRECISION = 2 * 1e6;

interface PositionOpenedEvent {
  wethAmount: ethers.BigNumberish;
  price: ethers.BigNumberish;
}

describe("RockOnyxDeltaNeutralVault", function () {
  let admin: Signer,
    user1: Signer,
    user2: Signer,
    user3: Signer,
    user4: Signer,
    user5: Signer;

  let optionsReceiver: Signer;

  let rockOnyxDeltaNeutralVaultContract: Contracts.RockOnyxDeltaNeutralVault;
  let onchainRockOnyxUSDTVaultContract: Contracts.RockOnyxDeltaNeutralVault;
  let usdc: Contracts.IERC20;
  let usdce: Contracts.IERC20;
  let wsteth: Contracts.IERC20;
  let weth: Contracts.IERC20;

  let aevoContract: Contracts.Aevo;

  const usdcImpersonatedSigner = USDC_IMPERSONATED_SIGNER_ADDRESS[chainId];
  const usdceImpersonatedSigner = USDCE_IMPERSONATED_SIGNER_ADDRESS[chainId];
  const usdcAddress = USDC_ADDRESS[chainId] || "";
  const wstethAddress = WSTETH_ADDRESS[chainId] || "";
  const wethAddress = WETH_ADDRESS[chainId] || "";
  const swapRouterAddress = SWAP_ROUTER_ADDRESS[chainId];
  const aevoAddress = AEVO_ADDRESS[chainId];
  const aevoConnectorAddress = AEVO_CONNECTOR_ADDRESS[chainId];

  let camelotSwapContract: Contracts.CamelotSwap;

  async function deployCamelotSwapContract() {
    const factory = await ethers.getContractFactory("CamelotSwap");
    camelotSwapContract = await factory.deploy(swapRouterAddress);
    await camelotSwapContract.waitForDeployment();

    console.log(
      "Deployed Camelot Swap contract at address %s",
      await camelotSwapContract.getAddress()
    );
  }

  async function deployAevoContract() {
    const factory = await ethers.getContractFactory("Aevo");
    aevoContract = await factory.deploy(
      usdcAddress,
      aevoAddress,
      aevoConnectorAddress
    );
    await aevoContract.waitForDeployment();

    console.log(
      "Deployed AEVO contract at address %s",
      await aevoContract.getAddress()
    );
  }

  async function deployRockOnyxDeltaNeutralVault() {
    const rockOnyxDeltaNeutralVault = await ethers.getContractFactory(
      "RockOnyxDeltaNeutralVault"
    );

    rockOnyxDeltaNeutralVaultContract = await rockOnyxDeltaNeutralVault.deploy(
      usdcAddress,
      await camelotSwapContract.getAddress(),
      await aevoContract.getAddress(),
      await optionsReceiver.getAddress(),
      wethAddress,
      wstethAddress
    );
    await rockOnyxDeltaNeutralVaultContract.waitForDeployment();

    console.log(
      "deploy rockOnyxDeltaNeutralVaultContract successfully: %s",
      await rockOnyxDeltaNeutralVaultContract.getAddress()
    );
  }

  beforeEach(async function () {
    [admin, optionsReceiver, user1, user2, user3, user4] =
      await ethers.getSigners();

    usdc = await ethers.getContractAt("IERC20", usdcAddress);

    wsteth = await ethers.getContractAt("IERC20", wstethAddress);
    weth = await ethers.getContractAt("IERC20", wethAddress);
    await deployCamelotSwapContract();
    await deployAevoContract();
    await deployRockOnyxDeltaNeutralVault();
  });

  // Helper function for deposit
  async function deposit(sender: Signer, amount: BigNumberish) {
    await usdc
      .connect(sender)
      .approve(await rockOnyxDeltaNeutralVaultContract.getAddress(), amount);

    await rockOnyxDeltaNeutralVaultContract.connect(sender).deposit(amount);
  }

  async function transferUsdcForUser(from: Signer, to: Signer, amount: number) {
    const transferTx = await usdc.connect(from).transfer(to, amount);
    await transferTx.wait();
  }

  async function logAndReturnTotalValueLock() {
    const totalValueLocked = await rockOnyxDeltaNeutralVaultContract
      .connect(admin)
      .totalValueLocked();

    console.log("totalValueLocked %s", totalValueLocked);

    return totalValueLocked;
  }

  // define function getWstEthPrice
  async function getWstEthPrice() {
    const wstEthAmount = 1; // we convert 1 wstEth to usdc
    const price = await camelotSwapContract.getPriceOf(
      wstethAddress,
      wethAddress,
      BigInt(18),
      BigInt(18)
    );
    console.log("wstEthPrice %s", price);

    // convert wstEth to eth, parse price BigInt to float
    const ethAmount = wstEthAmount * parseFloat(price.toString()) / 1e18;
    console.log("ethAmount %s", ethAmount);

    // get eth price in usdc
    const ethPrice = await camelotSwapContract.getPriceOf(
      wethAddress,
      usdcAddress,
      BigInt(18),
      BigInt(6)
    );
    console.log("ethPrice %s", ethPrice);

    // convert eth to usdc
    const usdcAmount = ethAmount * parseFloat(ethPrice.toString()) / 1e6;

    return usdcAmount;
  }

  async function getEthPrice() {
    // get current priceOf from CamelotSwapContract
    const _ethPrice = await camelotSwapContract.getPriceOf(
      wstethAddress,
      wethAddress,
      BigInt(18),
      BigInt(18)
    );
    // parse priceOf to float
    const ethPrice = parseFloat(_ethPrice.toString()) / 1e18;
    console.log("ethPrice %s", ethPrice);
    return ethPrice;
  }

  it("seed data", async function () {
    const usdcSigner = await ethers.getImpersonatedSigner(
      usdcImpersonatedSigner
    );

    await transferUsdcForUser(usdcSigner, user1, 10000 * 1e6);
    await transferUsdcForUser(usdcSigner, user2, 10000 * 1e6);
    await transferUsdcForUser(usdcSigner, user3, 10000 * 1e6);
    await transferUsdcForUser(usdcSigner, user4, 10000 * 1e6);
    await transferUsdcForUser(usdcSigner, optionsReceiver, 1000 * 1e6);
  });

  it("user deposit -> withdraw, do not deposit to perp dex", async function () {
    console.log(
      "-------------deposit to rockOnyxDeltaNeutralVault---------------"
    );
    await deposit(user1, 10 * 1e6);
    await deposit(user2, 100 * 1e6);

    let totalValueLock = await logAndReturnTotalValueLock();
    expect(totalValueLock).to.approximately(110 * 1e6, PRECISION);

    console.log("-------------Users initial withdrawals---------------");
    const initiateWithdrawalTx1 = await rockOnyxDeltaNeutralVaultContract
      .connect(user2)
      .initiateWithdrawal(100 * 1e6);
    await initiateWithdrawalTx1.wait();

    console.log("-------------handleWithdrawalFunds---------------");
    // 49957050 49957050
    const handleWithdrawalFundsTx = await rockOnyxDeltaNeutralVaultContract
      .connect(admin)
      .handleWithdrawalFunds(49957050n, 49957050n);
    await initiateWithdrawalTx1.wait();

    console.log("-------------complete withdrawals---------------");
    let user2Balance = await usdc.connect(user2).balanceOf(user2);
    console.log("usdc of user before withdraw %s", user2Balance);

    const completeWithdrawalTx = await rockOnyxDeltaNeutralVaultContract
      .connect(user2)
      .completeWithdrawal(100 * 1e6);
    await completeWithdrawalTx.wait();

    let user1BalanceAfterWithdraw = await usdc.connect(user2).balanceOf(user2);
    console.log("usdc of user after withdraw %s", user1BalanceAfterWithdraw);
    expect(user1BalanceAfterWithdraw).to.approximately(
      user2Balance + BigInt(100 * 1e6),
      PRECISION
    );
  });

  it("user deposit -> open position -> close position -> withdraw, do not deposit to perp dex", async function () {
    console.log(
      "-------------deposit to rockOnyxDeltaNeutralVault---------------"
    );
    await deposit(user1, 10 * 1e6);
    await deposit(user2, 100 * 1e6);

    let totalValueLock = await logAndReturnTotalValueLock();
    expect(totalValueLock).to.approximately(110 * 1e6, PRECISION);

    console.log("-------------open position---------------");
    const openPositionTx = await rockOnyxDeltaNeutralVaultContract
      .connect(admin)
      .openPosition(BigInt(0.01 * 1e18));
    await openPositionTx.wait();

    console.log("-------------close position---------------");
    const closePositionTx = await rockOnyxDeltaNeutralVaultContract
      .connect(admin)
      .closePosition(BigInt(0.01 * 1e18));
    await closePositionTx.wait();

    console.log("-------------Users initial withdrawals---------------");
    const initiateWithdrawalTx1 = await rockOnyxDeltaNeutralVaultContract
      .connect(user2)
      .initiateWithdrawal(100 * 1e6);
    await initiateWithdrawalTx1.wait();

    console.log("-------------handleWithdrawalFunds---------------");
    // 49957050 49957050
    const handleWithdrawalFundsTx = await rockOnyxDeltaNeutralVaultContract
      .connect(admin)
      .handleWithdrawalFunds(49957050n, 49957050n);
    await initiateWithdrawalTx1.wait();

    console.log("-------------complete withdrawals---------------");
    let user2Balance = await usdc.connect(user2).balanceOf(user2);
    console.log("usdc of user before withdraw %s", user2Balance);

    const completeWithdrawalTx = await rockOnyxDeltaNeutralVaultContract
      .connect(user2)
      .completeWithdrawal(100 * 1e6);
    await completeWithdrawalTx.wait();

    let user1BalanceAfterWithdraw = await usdc.connect(user2).balanceOf(user2);
    console.log("usdc of user after withdraw %s", user1BalanceAfterWithdraw);
    expect(user1BalanceAfterWithdraw).to.approximately(
      user2Balance + BigInt(100 * 1e6),
      PRECISION
    );
  });

  it("user deposit -> open position -> deposit to vender -> withdraw", async function () {
    console.log(
      "-------------deposit to rockOnyxDeltaNeutralVault---------------"
    );
    await deposit(user1, 10 * 1e6);
    await deposit(user2, 100 * 1e6);

    let totalValueLock = await logAndReturnTotalValueLock();
    expect(totalValueLock).to.approximately(110 * 1e6, PRECISION);

    console.log("-------------open position---------------");
    const openPositionTx = await rockOnyxDeltaNeutralVaultContract
      .connect(admin)
      .openPosition(BigInt(0.01 * 1e18));
    await openPositionTx.wait();

    console.log("-------------close position---------------");
    const closePositionTx = await rockOnyxDeltaNeutralVaultContract
      .connect(admin)
      .closePosition(BigInt(0.005 * 1e18));
    await closePositionTx.wait();

    console.log("-------------deposit to vendor on aevo---------------");
    await rockOnyxDeltaNeutralVaultContract.connect(admin).depositToVendor({
      value: ethers.parseEther("0.000159539385325246"),
    });

    totalValueLock = await logAndReturnTotalValueLock();
    expect(totalValueLock).to.approximately(110 * 1e6, PRECISION);

    console.log("-------------Users initial withdrawals---------------");
    const initiateWithdrawalTx1 = await rockOnyxDeltaNeutralVaultContract
      .connect(user2)
      .initiateWithdrawal(100 * 1e6);
    await initiateWithdrawalTx1.wait();

    console.log("-------------handleWithdrawalFunds---------------");
    // 49957050 49957050
    const usdcAmount = 49957050n;
    console.log("usdcAmount %s", usdcAmount);

    await usdc
      .connect(optionsReceiver)
      .approve(
        await rockOnyxDeltaNeutralVaultContract.getAddress(),
        usdcAmount
      );

    const handleWithdrawalFundsTx = await rockOnyxDeltaNeutralVaultContract
      .connect(optionsReceiver)
      .handleWithdrawalFunds(49957050n, 49957050n);
    await initiateWithdrawalTx1.wait();

    console.log("-------------complete withdrawals---------------");
    let user2Balance = await usdc.connect(user2).balanceOf(user2);
    console.log("usdc of user before withdraw %s", user2Balance);

    const completeWithdrawalTx = await rockOnyxDeltaNeutralVaultContract
      .connect(user2)
      .completeWithdrawal(100 * 1e6);
    await completeWithdrawalTx.wait();

    let user1BalanceAfterWithdraw = await usdc.connect(user2).balanceOf(user2);
    console.log("usdc of user after withdraw %s", user1BalanceAfterWithdraw);
    expect(user1BalanceAfterWithdraw).to.approximately(
      user2Balance + BigInt(99 * 1e6),
      PRECISION
    );
  });

  it("user deposit1 -> open position -> deposit to vender -> user deposit2 -> open position -> deposit to vender -> withdraw", async function () {
    console.log(
      "-------------deposit1 to rockOnyxDeltaNeutralVault---------------"
    );
    await deposit(user1, 10 * 1e6);
    await deposit(user2, 100 * 1e6);
    let totalValueLock = await logAndReturnTotalValueLock();
    expect(totalValueLock).to.approximately(110 * 1e6, PRECISION);

    console.log("-------------open position1---------------");
    const openPositionTx = await rockOnyxDeltaNeutralVaultContract
      .connect(admin)
      .openPosition(BigInt(0.01 * 1e18));
    await openPositionTx.wait();

    console.log("-------------deposit to vendor on aevo---------------");
    await rockOnyxDeltaNeutralVaultContract.connect(admin).depositToVendor({
      value: ethers.parseEther("0.000159539385325246"),
    });

    totalValueLock = await logAndReturnTotalValueLock();
    expect(totalValueLock).to.approximately(110 * 1e6, PRECISION);

    console.log(
      "-------------deposit2 to rockOnyxDeltaNeutralVault---------------"
    );
    await deposit(user2, 100 * 1e6);

    totalValueLock = await logAndReturnTotalValueLock();
    expect(totalValueLock).to.approximately(210 * 1e6, PRECISION);

    console.log("-------------open position 2---------------");
    const openPosition1Tx = await rockOnyxDeltaNeutralVaultContract
      .connect(admin)
      .openPosition(BigInt(0.01 * 1e18));
    await openPositionTx.wait();

    console.log("-------------deposit to vendor on aevo---------------");
    await rockOnyxDeltaNeutralVaultContract.connect(admin).depositToVendor({
      value: ethers.parseEther("0.000159539385325246"),
    });

    totalValueLock = await logAndReturnTotalValueLock();
    expect(totalValueLock).to.approximately(210 * 1e6, PRECISION);

    console.log("-------------Users initial withdrawals---------------");
    const initiateWithdrawalTx1 = await rockOnyxDeltaNeutralVaultContract
      .connect(user2)
      .initiateWithdrawal(100 * 1e6);
    await initiateWithdrawalTx1.wait();

    console.log("-------------handleWithdrawalFunds---------------");
    // 49957050 49957050
    const usdcAmount = 49957050n;
    console.log("usdcAmount %s", usdcAmount);

    await usdc
      .connect(optionsReceiver)
      .approve(
        await rockOnyxDeltaNeutralVaultContract.getAddress(),
        usdcAmount
      );

    const handleWithdrawalFundsTx = await rockOnyxDeltaNeutralVaultContract
      .connect(optionsReceiver)
      .handleWithdrawalFunds(49957050n, 49957050n);
    await initiateWithdrawalTx1.wait();

    console.log("-------------complete withdrawals---------------");
    let user2Balance = await usdc.connect(user2).balanceOf(user2);
    console.log("usdc of user before withdraw %s", user2Balance);

    const completeWithdrawalTx = await rockOnyxDeltaNeutralVaultContract
      .connect(user2)
      .completeWithdrawal(100 * 1e6);
    await completeWithdrawalTx.wait();

    let user1BalanceAfterWithdraw = await usdc.connect(user2).balanceOf(user2);
    console.log("usdc of user after withdraw %s", user1BalanceAfterWithdraw);
    expect(user1BalanceAfterWithdraw).to.approximately(
      user2Balance + BigInt(100 * 1e6),
      PRECISION
    );
  });

  it("user deposit -> deposit to vendor -> open position -> sync profit -> withdraw -> close position -> complete withdraw", async function () {
    console.log(
      "-------------deposit to rockOnyxDeltaNeutralVault---------------"
    );

    const inititalDeposit = 10 + 100;

    await deposit(user1, 10 * 1e6);
    await deposit(user2, 100 * 1e6);

    let totalValueLock = await logAndReturnTotalValueLock();
    // parse totalValueLock to float
    let tvlNumber = parseFloat(totalValueLock.toString()) / 1e6;
    
    expect(totalValueLock).to.approximately(inititalDeposit * 1e6, PRECISION);

    console.log("-------------deposit to vendor on aevo---------------");
    await rockOnyxDeltaNeutralVaultContract.connect(admin).depositToVendor({
      value: ethers.parseEther("0.000159539385325246"),
    });

    console.log("-------------open position---------------");
    let ethPrice = await getEthPrice();

    // calculate eth amount for totalvaluelocked / 2 usd amount
    // round ethAmount to 2 decimal places
    const ethAmount = parseFloat(((tvlNumber / 2) / ethPrice).toFixed(2));
    console.log("ethAmount %s", ethAmount);

    const openPositionTx = await rockOnyxDeltaNeutralVaultContract
      .connect(admin)
      .openPosition(BigInt(ethAmount * 1e18));
    await openPositionTx.wait();

    totalValueLock = await logAndReturnTotalValueLock();
    expect(totalValueLock).to.approximately(inititalDeposit * 1e6, PRECISION);

    console.log("-------------sync derpDex balance---------------");
    // assume that the funding fee return 0.01% every 1 hour
    // we sync balance after 8 hours
    const dexBalance = (tvlNumber / 2) * 0.0001 * 8;
    console.log("dexBalance %s", dexBalance);

    const syncDerpDexBalanceTx = await rockOnyxDeltaNeutralVaultContract
      .connect(admin)
      .syncBalance(dexBalance);
    await syncDerpDexBalanceTx.wait();

    // get current price per share from contract
    const pricePerShare = await rockOnyxDeltaNeutralVaultContract
      .connect(admin)
      .pricePerShare();
    console.log("pricePerShare %s", pricePerShare);
    expect(pricePerShare).to.greaterThan(1 * 1e6);

    totalValueLock = await logAndReturnTotalValueLock();
    expect(totalValueLock).to.approximately((inititalDeposit / 2 + dexBalance) * 1e6, PRECISION);

    console.log("-------------Users initial withdrawals---------------");
    const withdrawalShares = 100;
    const withdrawalAmount = (withdrawalShares * parseFloat(pricePerShare.toString())) / 1e6;
    console.log("withdrawalAmount %s", withdrawalAmount);

    const initiateWithdrawalTx1 = await rockOnyxDeltaNeutralVaultContract
      .connect(user2)
      .initiateWithdrawal(withdrawalShares * 1e6);
    await initiateWithdrawalTx1.wait();

    console.log("------------- close position to release fund for user ---------------");
    // calculate eth amount from withdrawalAmount
    ethPrice = await getEthPrice();
    let withdrawalEthAmount = withdrawalAmount / ethPrice;
    withdrawalEthAmount = Math.ceil(withdrawalEthAmount * 100) / 100;
    console.log("ethAmountFromUsd %s", withdrawalEthAmount);

    const closePositionTx = await rockOnyxDeltaNeutralVaultContract
      .connect(admin)
      .closePosition(BigInt(withdrawalEthAmount * 1e18));
    await closePositionTx.wait();

    

    console.log("-------------handleWithdrawalFunds---------------");
    // 49920910 181838190
    const usdcAmount = 181838190n;
    console.log("usdcAmount %s", usdcAmount);

    await usdc
      .connect(optionsReceiver)
      .approve(
        await rockOnyxDeltaNeutralVaultContract.getAddress(),
        usdcAmount
      );

    const handleWithdrawalFundsTx = await rockOnyxDeltaNeutralVaultContract
      .connect(optionsReceiver)
      .handleWithdrawalFunds(49920910n, 181838190n);
    await initiateWithdrawalTx1.wait();

    console.log("-------------complete withdrawals---------------");
    let user2Balance = await usdc.connect(user2).balanceOf(user2);
    console.log("usdc of user before withdraw %s", user2Balance);

    const completeWithdrawalTx = await rockOnyxDeltaNeutralVaultContract
      .connect(user2)
      .completeWithdrawal(100 * 1e6);
    await completeWithdrawalTx.wait();

    let user1BalanceAfterWithdraw = await usdc.connect(user2).balanceOf(user2);
    console.log("usdc of user after withdraw %s", user1BalanceAfterWithdraw);
    expect(user1BalanceAfterWithdraw).to.approximately(
      user2Balance + BigInt(230 * 1e6),
      PRECISION
    );
  });

  it("user deposit -> open position -> close position", async function () {
    console.log(
      "-------------deposit to rockOnyxDeltaNeutralVault---------------"
    );
    const contractAddress =
      await rockOnyxDeltaNeutralVaultContract.getAddress();
    await deposit(user1, 1000 * 1e6);
    await deposit(user2, 1000 * 1e6);

    let totalValueLock = await logAndReturnTotalValueLock();
    expect(totalValueLock).to.approximately(2000 * 1e6, PRECISION);

    console.log("-------------open position---------------");

    var openEvent = rockOnyxDeltaNeutralVaultContract.getEvent("PositionOpened");
    var closeEvent =
      rockOnyxDeltaNeutralVaultContract.getEvent("PositionClosed");

    await rockOnyxDeltaNeutralVaultContract.on(
      closeEvent,
      async (
        usdAmount: any,
        wstEthEthPrice: any,
        ethToUsdPrice: any,
        ethAmountFomUsd: any,
        wstEthAmountFomEth: any,
        convertedWEthAmount: any,
        convertedUsdAmount: any
      ) => {
        console.log(
          "Position closed - USD Amount: %s",
          usdAmount.toString(),
          "WSTETH/ETH Price: %s",
          wstEthEthPrice.toString(),
          "ETH/USD Price: %s",
          ethToUsdPrice.toString(),
          "ETH Amount From USD: %s",
          ethAmountFomUsd.toString(),
          "WSTETH Amount From ETH: %s",
          wstEthAmountFomEth.toString(),
          "Converted WETH Amount: %s",
          convertedWEthAmount.toString(),
          "Converted USD Amount: %s",
          convertedUsdAmount.toString()
        );

        expect(usdAmount).to.approximately(convertedUsdAmount, 5 * 1e6);
      }
    );

    await rockOnyxDeltaNeutralVaultContract.on(
      openEvent,
      async (
        usdAmount: any,
        price: any,
        wethAmount: any,
        wstEthAmount: any
      ) => {
        console.log("-------------close position---------------");

        console.log("test 1 %s", contractAddress);

        const wstEthVaultBalance = await wsteth.balanceOf(contractAddress);
        console.log(
          "RockOnyxDeltaNeutralVault balance of WSTETH: %s",
          (Number(wstEthVaultBalance) / 1e18).toFixed(8)
        );

        const wstEthEthPrice = await camelotSwapContract.getPriceOf(
          wstethAddress,
          wethAddress,
          BigInt(18),
          BigInt(18)
        );
        console.log("WSTETH/ETH Price: %s", Number(wstEthEthPrice) / 1e18);

        const ethPrice = await camelotSwapContract.getPriceOf(
          wethAddress,
          usdcAddress,
          BigInt(18),
          BigInt(6)
        );
        console.log("WETH/USDC Price: %s", (Number(ethPrice) / 1e6).toFixed(8));

        // Convert WSTETH balance to ETH
        const ethVaultBalance =
          (Number(wstEthVaultBalance) * Number(wstEthEthPrice)) / 1e18;
        console.log("ethVaultBalance: %s", ethVaultBalance);

        // Convert ETH balance to USDC
        const usdcVaultBalance = parseInt(
          ((Number(ethVaultBalance) * Number(ethPrice)) / 1e18).toString()
        );
        console.log("usdcVaultBalance: %s", usdcVaultBalance);

        const closePositionTx = await rockOnyxDeltaNeutralVaultContract
          .connect(admin)
          .closePosition(BigInt(usdcVaultBalance));
        await closePositionTx.wait();
      }
    );

    const openPositionTx = await rockOnyxDeltaNeutralVaultContract
      .connect(admin)
      .openPosition(BigInt(0.01 * 1e18));
    await openPositionTx.wait();

    // add a sleep here to keep the main loop running while the event listener working
    await new Promise((resolve) => setTimeout(resolve, 3000));
  });
});
