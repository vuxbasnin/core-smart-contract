const { ethers } = require("hardhat");
import { expect } from "chai";

import * as Contracts from "../../typechain-types";
import {
  CHAINID,
  WETH_ADDRESS,
  USDC_ADDRESS,
  USDCE_ADDRESS,
  WSTETH_ADDRESS,
  ARB_ADDRESS,
  ETH_PRICE_FEED_ADDRESS,
  WSTETH__ETH_PRICE_FEED_ADDRESS,
  USDC_PRICE_FEED_ADDRESS,
  ARB_PRICE_FEED_ADDRESS
} from "../../constants";
import {
  Signer,
} from "ethers";

// const chainId: CHAINID = network.config.chainId;
const chainId: CHAINID = 42161;

describe("PriceConsumer test", function () {
  let admin: Signer;
  let priceConsumerContract: Contracts.PriceConsumer;
  let usdc: Contracts.IERC20;
  let usdce: Contracts.IERC20;
  let wsteth: Contracts.IERC20;
  let weth: Contracts.IERC20;
  let arb: Contracts.IERC20;

  const wethAddress = WETH_ADDRESS[chainId];
  const wstethAddress = WSTETH_ADDRESS[chainId];
  const usdceAddress = USDCE_ADDRESS[chainId];
  const usdcAddress = USDC_ADDRESS[chainId];
  const arbAddress = ARB_ADDRESS[chainId];
  
  const ethPriceFeed = ETH_PRICE_FEED_ADDRESS[chainId];
  const steth_ethPriceFeed = WSTETH__ETH_PRICE_FEED_ADDRESS[chainId];
  const usdcePriceFeed = USDC_PRICE_FEED_ADDRESS[chainId];
  const arbPriceFeed = ARB_PRICE_FEED_ADDRESS[chainId];

  async function deployPriceConsumerContract() {
    const factory = await ethers.getContractFactory("PriceConsumer");
    priceConsumerContract = await factory.deploy(
      [wethAddress, wstethAddress, usdceAddress, arbAddress],
      [usdcAddress, wethAddress, usdcAddress, usdcAddress],
      [ethPriceFeed, steth_ethPriceFeed, usdcePriceFeed, arbPriceFeed]
    );
    await priceConsumerContract.waitForDeployment();

    console.log(
      "Deployed price consumer contract at address %s",
      await priceConsumerContract.getAddress()
    );
  }

  beforeEach(async function () {
    [admin] = await ethers.getSigners();
    weth = await ethers.getContractAt("IERC20", wethAddress);
    wsteth = await ethers.getContractAt("IERC20", wstethAddress);
    usdce = await ethers.getContractAt("IERC20", usdceAddress);
    usdc = await ethers.getContractAt("IERC20", usdcAddress);
    arb = await ethers.getContractAt("IERC20", arbAddress);
    
    await deployPriceConsumerContract();
  });

  it("get token price", async function () {
    console.log("-------------get ethPrice---------------");
    const getEthPrice = await priceConsumerContract
      .connect(admin)
      .getPriceOf(weth, usdc);
      console.log('1 eth = %s usd', getEthPrice);

    const getUsdcEthPrice = await priceConsumerContract
      .connect(admin)
      .getPriceOf(usdc, weth);
      console.log('1 usd = %s weth', getUsdcEthPrice);

    console.log("-------------get wstEth_EthPrice---------------");
    const getWstEth_EthPrice = await priceConsumerContract
      .connect(admin)
      .getPriceOf(wsteth, weth);
      console.log('1 wsteth = %s eth', getWstEth_EthPrice );

      const getEth_WstEthPrice = await priceConsumerContract
      .connect(admin)
      .getPriceOf(weth, wsteth);
      console.log('1 eth = %s wsteth', getEth_WstEthPrice );

    console.log("-------------getUsdcPrice---------------");
    const getUsdcPrice = await priceConsumerContract
      .connect(admin)
      .getPriceOf(usdce, usdc);
      console.log('1 usdc = %s usd', getUsdcPrice);

    console.log("-------------getArbPrice---------------");
    const getArbPrice = await priceConsumerContract
      .connect(admin)
      .getPriceOf(arb, usdc);
      console.log('1 arb = %s usd', getArbPrice);
  });

  it("update price feed", async function () {
    const newPriceFeed = ARB_PRICE_FEED_ADDRESS[chainId];
    console.log('newPriceFeed', newPriceFeed);

    await priceConsumerContract
      .connect(admin)
      .updatePriceFeed(weth, usdc, newPriceFeed);

      const newPriceFeedAddress = await priceConsumerContract
      .connect(admin)
      .getPriceFeed(weth, usdc);

      console.log('newPriceFeedAddress', newPriceFeedAddress);
      expect(newPriceFeed).to.equal(newPriceFeedAddress);
  });
});