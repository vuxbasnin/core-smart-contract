const { ethers, network } = require("hardhat");
import { expect } from "chai";

import * as Contracts from "../../typechain-types";
import {
  CHAINID,
  WETH_ADDRESS,
  USDC_ADDRESS,
  SWAP_ROUTER_ADDRESS,
  AEVO_ADDRESS,
  AEVO_CONNECTOR_ADDRESS,
  USDC_IMPERSONATED_SIGNER_ADDRESS,
  ETH_PRICE_FEED_ADDRESS,
  EZTETH__ETH_PRICE_FEED_ADDRESS,
  EZETH_ADDRESS,
  ZIRCUIT_DEPOSIT_ADDRESS,
  RENZO_DEPOSIT_ADDRESS,
} from "../../constants";
import { BigNumberish, Signer } from "ethers";

const chainId: CHAINID = network.config.chainId;
console.log("chain id :", chainId);
const PRECISION = 2 * 1e6;

describe("RockOnyxDeltaNeutralVault", function () {
  let admin: Signer,
    user1: Signer,
    user2: Signer,
    user3: Signer,
    user4: Signer;

  let optionsReceiver: Signer;

  let renzoRestakingDNVault: Contracts.RenzoRestakingDeltaNeutralVault;
  let usdc: Contracts.IERC20;
  let weth: Contracts.IERC20;

  const usdcImpersonatedSigner = USDC_IMPERSONATED_SIGNER_ADDRESS[chainId];
  const usdcAddress = USDC_ADDRESS[chainId] || "";
  const wethAddress = WETH_ADDRESS[chainId] || "";
  const ezEthAddress = EZETH_ADDRESS[chainId] || "";
  const swapFactoryAddress = SWAP_ROUTER_ADDRESS[chainId];
  const aevoAddress = AEVO_ADDRESS[chainId];
  const aevoConnectorAddress = AEVO_CONNECTOR_ADDRESS[chainId];
  const ethPriceFeed = ETH_PRICE_FEED_ADDRESS[chainId];
  const ezEth_EthPriceFeed = EZTETH__ETH_PRICE_FEED_ADDRESS[chainId];
  const renzoDepositAddress = RENZO_DEPOSIT_ADDRESS[chainId];
  const zircuitDepositAddress = ZIRCUIT_DEPOSIT_ADDRESS[chainId];

  let priceConsumerContract: Contracts.PriceConsumer;
  let uniSwapContract: Contracts.UniSwap;

  async function deployPriceConsumerContract() {
    const factory = await ethers.getContractFactory("PriceConsumer");
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
      swapFactoryAddress,
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
    [admin, optionsReceiver, user1, user2, user3, user4] =
      await ethers.getSigners();

    usdc = await ethers.getContractAt("IERC20", usdcAddress);
    weth = await ethers.getContractAt("IERC20", wethAddress);
    await deployPriceConsumerContract();
    await deployUniSwapContract();
    await deployRenzoRestakingDeltaNeutralVault();
  });

  // Helper function for deposit
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

  async function getEthPrice() {
    // get current priceOf from uniSwapContract
    const _ethPrice = await uniSwapContract.getPriceOf(
      wethAddress,
      usdcAddress
    );
    // parse priceOf to float
    const ethPrice = parseFloat(_ethPrice.toString()) / 1e6;
    console.log("ethPrice %s", ethPrice);
    return ethPrice;
  }

  it("seed data", async function () {
    const usdcSigner = await ethers.getImpersonatedSigner(
      usdcImpersonatedSigner
    );

    await transferUsdcForUser(usdcSigner, user1, 100000 * 1e6);
    await transferUsdcForUser(usdcSigner, user2, 100000 * 1e6);
    await transferUsdcForUser(usdcSigner, user3, 100000 * 1e6);
    await transferUsdcForUser(usdcSigner, user4, 100000 * 1e6);
    await transferUsdcForUser(usdcSigner, optionsReceiver, 10000 * 1e6);
  });

  it("user deposit -> deposit to perp dex -> deposit to renzo -> deposit to zircuit", async function () {
    console.log(
      "-------------deposit to vault---------------"
    );
    await deposit(user1, 10 * 1e6);
    await deposit(user2, 100 * 1e6);

    let totalValueLock = await logAndReturnTotalValueLock();
    expect(totalValueLock).to.approximately(110 * 1e6, PRECISION);

    console.log("-------------deposit to vendor on aevo---------------");
    await renzoRestakingDNVault.connect(admin).depositToVendor(500000);
    totalValueLock = await logAndReturnTotalValueLock();
    expect(totalValueLock).to.approximately(110 * 1e6, PRECISION);

    console.log("-------------open position---------------");
    const openPositionTx = await renzoRestakingDNVault
      .connect(admin)
      .openPosition(BigInt(0.01 * 1e18));
    await openPositionTx.wait();
  });
});
