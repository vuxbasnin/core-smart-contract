const { ethers, network } = require("hardhat");
import { expect } from "chai";

import * as Contracts from "../../typechain-types";
import {
  CHAINID,
  WETH_ADDRESS,
  USDC_ADDRESS,
  USDCE_ADDRESS,
  WSTETH_ADDRESS,
  SWAP_ROUTER_ADDRESS,
  AEVO_ADDRESS,
  AEVO_CONNECTOR_ADDRESS,
  USDC_IMPERSONATED_SIGNER_ADDRESS,
  USDCE_IMPERSONATED_SIGNER_ADDRESS,
  ETH_PRICE_FEED_ADDRESS,
  WSTETH__ETH_PRICE_FEED_ADDRESS,
  USDC_PRICE_FEED_ADDRESS,
  ARB_PRICE_FEED_ADDRESS,
  EZETH_ADDRESS,
  ZIRCUIT_DEPOSIT_ADDRESS,
  RENZO_DEPOSIT_ADDRESS,
} from "../../constants";
import { BigNumberish, Signer } from "ethers";

// const chainId: CHAINID = network.config.chainId;
const chainId: CHAINID = 42161;
const PRECISION = 2 * 1e6;

describe("RockOnyxDeltaNeutralVault", function () {
  let admin: Signer,
    user1: Signer,
    user2: Signer,
    user3: Signer,
    user4: Signer,
    user5: Signer;

  let optionsReceiver: Signer;

  let restakingDNVault: Contracts.RockOnyxDeltaNeutralVault;
  let onchainRockOnyxUSDTVaultContract: Contracts.RockOnyxDeltaNeutralVault;
  let usdc: Contracts.IERC20;
  let usdce: Contracts.IERC20;
  let wsteth: Contracts.IERC20;
  let weth: Contracts.IERC20;

  let aevoContract: Contracts.Aevo;

  const usdcImpersonatedSigner = USDC_IMPERSONATED_SIGNER_ADDRESS[chainId];
  const usdceImpersonatedSigner = USDCE_IMPERSONATED_SIGNER_ADDRESS[chainId];
  const usdcAddress = USDC_ADDRESS[chainId] || "";
  const usdceAddress = USDCE_ADDRESS[chainId] || "";
  const wstethAddress = WSTETH_ADDRESS[chainId] || "";
  const wethAddress = WETH_ADDRESS[chainId] || "";
  const ezEthAddress = EZETH_ADDRESS[chainId] || "";
  const swapRouterAddress = SWAP_ROUTER_ADDRESS[chainId];
  const aevoAddress = AEVO_ADDRESS[chainId];
  const aevoConnectorAddress = AEVO_CONNECTOR_ADDRESS[chainId];
  const ethPriceFeed = ETH_PRICE_FEED_ADDRESS[chainId];
  const wsteth_ethPriceFeed = WSTETH__ETH_PRICE_FEED_ADDRESS[chainId];
  const usdcePriceFeed = USDC_PRICE_FEED_ADDRESS[chainId];

  const renzoDepositAddress = RENZO_DEPOSIT_ADDRESS[chainId];
  const zircuitDepositAddress = ZIRCUIT_DEPOSIT_ADDRESS[chainId];

  let priceConsumerContract: Contracts.PriceConsumer;
  let camelotSwapContract: Contracts.CamelotSwap;

  async function deployPriceConsumerContract() {
    const factory = await ethers.getContractFactory("PriceConsumer");
    priceConsumerContract = await factory.deploy(
      [wethAddress, wstethAddress, usdceAddress],
      [usdcAddress, wethAddress, usdcAddress],
      [ethPriceFeed, wsteth_ethPriceFeed, usdcePriceFeed]
    );
    await priceConsumerContract.waitForDeployment();

    console.log(
      "Deployed price consumer contract at address %s",
      await priceConsumerContract.getAddress()
    );
  }

  async function deployCamelotSwapContract() {
    const factory = await ethers.getContractFactory("CamelotSwap");
    camelotSwapContract = await factory.deploy(
      swapRouterAddress,
      priceConsumerContract.getAddress()
    );
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
    const restakingDeltaNeutralVault = await ethers.getContractFactory(
      "RestakingDeltaNeutralVault"
    );

    restakingDNVault = await restakingDeltaNeutralVault.deploy(
      usdcAddress,
      wethAddress,
      await camelotSwapContract.getAddress(),
      await aevoContract.getAddress(),
      await optionsReceiver.getAddress(),
      ezEthAddress,
      BigInt(1 * 1e6),
      [renzoDepositAddress, zircuitDepositAddress]
    );
    await restakingDNVault.waitForDeployment();

    console.log(
      "deploy rockOnyxDeltaNeutralVaultContract successfully: %s",
      await restakingDNVault.getAddress()
    );
  }

  beforeEach(async function () {
    [admin, optionsReceiver, user1, user2, user3, user4] =
      await ethers.getSigners();

    usdc = await ethers.getContractAt("IERC20", usdcAddress);
    weth = await ethers.getContractAt("IERC20", wethAddress);
    await deployPriceConsumerContract();
    await deployCamelotSwapContract();
    console.log("here");
    await deployAevoContract();
    await deployRockOnyxDeltaNeutralVault();
  });

  // Helper function for deposit
  async function deposit(sender: Signer, amount: BigNumberish) {
    await usdc
      .connect(sender)
      .approve(await restakingDNVault.getAddress(), amount);

    await restakingDNVault.connect(sender).deposit(amount);
  }

  async function transferUsdcForUser(from: Signer, to: Signer, amount: number) {
    const transferTx = await usdc.connect(from).transfer(to, amount);
    await transferTx.wait();
  }

  async function logAndReturnTotalValueLock() {
    const totalValueLocked = await restakingDNVault
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
      wethAddress
    );

    // convert wstEth to eth, parse price BigInt to float
    const ethAmount = (wstEthAmount * parseFloat(price.toString())) / 1e18;

    // get eth price in usdc
    const ethPrice = await camelotSwapContract.getPriceOf(
      wethAddress,
      usdcAddress
    );

    // convert eth to usdc
    const usdcAmount = (ethAmount * parseFloat(ethPrice.toString())) / 1e6;

    return usdcAmount;
  }

  // define function getWstEthPrice
  async function getWstEthToEthPrice() {
    const price = await camelotSwapContract.getPriceOf(
      wstethAddress,
      wethAddress
    );

    return price;
  }

  async function getEthPrice() {
    // get current priceOf from CamelotSwapContract
    const _ethPrice = await camelotSwapContract.getPriceOf(
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
  });
});
