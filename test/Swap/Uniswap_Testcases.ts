const { ethers } = require("hardhat");

import * as Contracts from "../../typechain-types";
import {
  CHAINID,
  WETH_ADDRESS,
  USDC_ADDRESS,
  USDCE_ADDRESS,
  WSTETH_ADDRESS,
  ARB_ADDRESS,
  SWAP_ROUTER_ADDRESS,
  ETH_PRICE_FEED_ADDRESS,
  UNISWAP_FACTORY_ADDRESS,
  USDC_PRICE_FEED_ADDRESS,
  ARB_PRICE_FEED_ADDRESS,
  EZETH_ADDRESS,
  EZTETH__ETH_PRICE_FEED_ADDRESS,
} from "../../constants";
import { Signer } from "ethers";
import { network } from "hardhat";

const chainId: CHAINID = network.config.chainId as CHAINID;
console.log("chainId", chainId);

describe("RockOnyxStableCoinVault", function () {
  let admin: Signer;
  let priceConsumerContract: Contracts.PriceConsumer;
  let USDC: Contracts.IERC20;
  let usdce: Contracts.IERC20;
  let EZETH: Contracts.IERC20;
  let WETH: Contracts.IERC20;
  let ARB: Contracts.IERC20;
  let slippage = BigInt(50);

  const usdcAddress = USDC_ADDRESS[chainId];
  const usdceAddress = USDCE_ADDRESS[chainId];
  const ezEthAddress = EZETH_ADDRESS[chainId];
  const wethAddress = WETH_ADDRESS[chainId];
  const arbAddress = ARB_ADDRESS[chainId];
  const swapRouterAddress = SWAP_ROUTER_ADDRESS[chainId];
  const uniswapFactoryAddress = UNISWAP_FACTORY_ADDRESS[chainId];

  const ethPriceFeed = ETH_PRICE_FEED_ADDRESS[chainId];
  const ezEth_ethPriceFeed = EZTETH__ETH_PRICE_FEED_ADDRESS[chainId];

  let uniswapContract: Contracts.UniSwap;

  async function deployPriceConsumerContract() {
    const factory = await ethers.getContractFactory("PriceConsumer");
    console.log("wethAddress, ezEthAddress %s %s", wethAddress, ezEthAddress);
    console.log("usdcAddress, wethAddress %s %s", usdcAddress, wethAddress);
    console.log(
      "ethPriceFeed, ezEth_ethPriceFeed %s %s",
      ethPriceFeed,
      ezEth_ethPriceFeed
    );

    priceConsumerContract = await factory.deploy(
      [wethAddress, ezEthAddress],
      [usdcAddress, wethAddress],
      [ethPriceFeed, ezEth_ethPriceFeed]
    );
    await priceConsumerContract.waitForDeployment();

    console.log(
      "Deployed price consumer contract at address %s",
      await priceConsumerContract.getAddress()
    );
  }

  async function deployUniswapContract() {
    const factory = await ethers.getContractFactory("UniSwap");
    console.log("swapRouterAddress %s", swapRouterAddress);
    console.log("uniswapFactoryAddress %s", swapRouterAddress);
    uniswapContract = await factory.deploy(
      swapRouterAddress,
      uniswapFactoryAddress,
      await priceConsumerContract.getAddress()
    );
    await uniswapContract.waitForDeployment();

    console.log(
      "Deployed Uniswap contract at address %s",
      await uniswapContract.getAddress()
    );
  }

  beforeEach(async function () {
    [admin] = await ethers.getSigners();

    console.log("usdcAddress %s", usdcAddress);
    console.log("ezEthAddress %s", ezEthAddress);
    console.log("wethAddress %s", wethAddress);

    USDC = await ethers.getContractAt("IERC20", usdcAddress);
    EZETH = await ethers.getContractAt("IERC20", ezEthAddress);
    WETH = await ethers.getContractAt("IERC20", wethAddress);
    console.log("here");

    await deployPriceConsumerContract();
    await deployUniswapContract();
  });

  it("swap 2eth to wsteth%", async function () {
    console.log("-------------swap eth to wsteth---------------");
    // const ethSigner = await ethers.getImpersonatedSigner(
    //   "0xD6153F5af5679a75cC85D8974463545181f48772"
    // );
    const [ethSigner] = await ethers.getSigners();

    console.log("----Before swap----");
    console.log(
      "eth amount %s",
      await ethers.provider.getBalance(await ethSigner.getAddress())
    );
    console.log(
      "ezETH amount %s",
      await EZETH.connect(ethSigner).balanceOf(await ethSigner.getAddress())
    );
    const swapEthToWstEthTx = await uniswapContract
      .connect(ethSigner)
      .swapTo(await ethSigner.getAddress(), await WETH.getAddress(), BigInt(2 * 1e18), await EZETH.getAddress());

    await swapEthToWstEthTx.wait();
    console.log("Swap successfully");
    console.log("----After swap----");
    console.log(
      "eth amount %s",
      await ethers.provider.getBalance(await ethSigner.getAddress())
    );
    console.log(
      "wst eth amount %s",
      await EZETH.connect(ethSigner).balanceOf(await ethSigner.getAddress())
    );
  });
});
