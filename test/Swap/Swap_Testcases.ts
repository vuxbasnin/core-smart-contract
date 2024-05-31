const { ethers } = require("hardhat");

import * as Contracts from "../../typechain-types";
import {
  CHAINID,
  WETH_ADDRESS,
  USDC_ADDRESS,
  USDCE_ADDRESS,
  USDT_ADDRESS,
  DAI_ADDRESS,
  WSTETH_ADDRESS,
  ARB_ADDRESS,
  EZETH_ADDRESS,
  RSETH_ADDRESS,
  SWAP_ROUTER_ADDRESS,
  ETH_PRICE_FEED_ADDRESS,
  WSTETH_ETH_PRICE_FEED_ADDRESS,
  USDC_PRICE_FEED_ADDRESS,
  USDT_PRICE_FEED_ADDRESS,
  DAI_PRICE_FEED_ADDRESS,
  ARB_PRICE_FEED_ADDRESS,
} from "../../constants";
import {
  Signer,
} from "ethers";

// const chainId: CHAINID = network.config.chainId;
const chainId: CHAINID = 42161;

describe("CamelotSwap", function () {
  let admin: Signer;
  let priceConsumerContract: Contracts.PriceConsumer;
  let usdc: Contracts.IERC20;
  let usdce: Contracts.IERC20;
  let wsteth: Contracts.IERC20;
  let weth: Contracts.IERC20;
  let arb: Contracts.IERC20;
  let slippage = BigInt(50);

  const wethAddress = WETH_ADDRESS[chainId] ?? "";
  const wstethAddress = WSTETH_ADDRESS[chainId] ?? "";
  const ezEthAddress = EZETH_ADDRESS[chainId] || "";
  const rsEthAddress = RSETH_ADDRESS[chainId] || "";
  const usdceAddress = USDCE_ADDRESS[chainId] ?? "";
  const usdcAddress = USDC_ADDRESS[chainId] ?? "";
  const arbAddress = ARB_ADDRESS[chainId] ?? "";
  const usdtAddress = USDT_ADDRESS[chainId] || "";
  const daiAddress = DAI_ADDRESS[chainId] || "";

  const ethPriceFeed = ETH_PRICE_FEED_ADDRESS[chainId];
  const wsteth_ethPriceFeed = WSTETH_ETH_PRICE_FEED_ADDRESS[chainId];
  const usdcePriceFeed = USDC_PRICE_FEED_ADDRESS[chainId];
  const arbPriceFeed = ARB_PRICE_FEED_ADDRESS[chainId];

  let camelotSwapContract: Contracts.CamelotSwap;

  async function deployPriceConsumerContract() {
    const factory = await ethers.getContractFactory("PriceConsumer");
    priceConsumerContract = await factory.deploy(
      [wethAddress, wstethAddress, usdceAddress, arbAddress],
      [usdcAddress, wethAddress, usdcAddress, usdcAddress],
      [ethPriceFeed, wsteth_ethPriceFeed, usdcePriceFeed, arbPriceFeed]
    );
    await priceConsumerContract.waitForDeployment();

    console.log(
      "Deployed price consumer contract at address %s",
      await priceConsumerContract.getAddress()
    );
  }

  async function deployCamelotSwapContract() {
    const factory = await ethers.getContractFactory("CamelotSwap");
    camelotSwapContract = await factory.deploy(swapRouterAddress, priceConsumerContract.getAddress());
    await camelotSwapContract.waitForDeployment();

    console.log(
      "Deployed Camelot Swap contract at address %s",
      await camelotSwapContract.getAddress()
    );
  }

  async function deployUniswapContract() {
    const factory = await ethers.getContractFactory("Uniswap");
    camelotSwapContract = await factory.deploy(swapRouterAddress, priceConsumerContract.getAddress());
    await camelotSwapContract.waitForDeployment();

    console.log(
      "Deployed Camelot Swap contract at address %s",
      await camelotSwapContract.getAddress()
    );
  }

  beforeEach(async function () {
    [admin] = await ethers.getSigners();

    usdc = await ethers.getContractAt("IERC20", usdcAddress);
    usdce = await ethers.getContractAt("IERC20", usdceAddress);
    wsteth = await ethers.getContractAt("IERC20", wstethAddress);
    weth = await ethers.getContractAt("IERC20", wethAddress);
    arb = await ethers.getContractAt("IERC20", arbAddress);

    // await deployPriceConsumerContract();
    // await deployCamelotSwapContract();
  });

  it.skip("get token price", async function () {
    console.log("-------------get wsteth_eth_price and get eth_wsteth_price---------------");
    const getWstEth_EthPrice = await camelotSwapContract
      .connect(admin)
      .getPriceOf(wsteth, weth);
      console.log('1 wsteth = %s eth', getWstEth_EthPrice );

    console.log("-------------get eth_usdc_price and get usdc_eth_price---------------");
    const getEth_UsdPrice = await camelotSwapContract
      .connect(admin)
      .getPriceOf(weth, usdc);
      console.log('1 eth = %s usdc', getEth_UsdPrice );

    console.log("-------------get usdce_usdc_price and get usdc_usdce_price---------------");
    const getUsdce_UsdcPrice = await camelotSwapContract
      .connect(admin)
      .getPriceOf(usdce, usdc);
      console.log('1 usdce = %s usdc', getUsdce_UsdcPrice );
  });

  it.skip("swap 2eth to wsteth%", async function () {
    console.log("-------------swap eth to wsteth---------------");
    const ethSigner = await ethers.getImpersonatedSigner(
        "0x891af9013e202eea5ef1e14e32de01488f579b65"
      );

    await weth
      .connect(ethSigner)
      .approve(await camelotSwapContract.getAddress(), BigInt(100*1e18));
     
    console.log('----Before swap----');
    console.log('eth amount %s', await weth.connect(ethSigner).balanceOf(ethSigner));
    console.log('wst eth amount %s', await wsteth.connect(ethSigner).balanceOf(ethSigner));
    const swapEthToWstEthTx = await camelotSwapContract
      .connect(ethSigner)
      .swapTo(ethSigner, weth, BigInt(2*1e18), wsteth);
      await swapEthToWstEthTx.wait();
    console.log('----After swap----');
    console.log('eth amount %s', await weth.connect(ethSigner).balanceOf(ethSigner));
    console.log('wst eth amount %s', await wsteth.connect(ethSigner).balanceOf(ethSigner));
  });

  it.skip("swap 2wsteth to eth%", async function () {
    console.log("-------------swap wsteth to eth---------------");
    const wstethSigner = await ethers.getImpersonatedSigner(
        "0xbb0b4642492b275f154e415fc52dacc931103fd9"
      );

    await wsteth
      .connect(wstethSigner)
      .approve(await camelotSwapContract.getAddress(), BigInt(100*1e18));

    console.log('----Before swap----');
    console.log('eth amount %s', await weth.connect(wstethSigner).balanceOf(wstethSigner));
    console.log('wst eth amount %s', await wsteth.connect(wstethSigner).balanceOf(wstethSigner));
    const swapWstEthToEthTx = await camelotSwapContract
      .connect(wstethSigner)
      .swapTo(wstethSigner, wsteth, BigInt(2*1e18), weth);
      await swapWstEthToEthTx.wait();
    console.log('----After swap----');
    console.log('eth amount %s', await weth.connect(wstethSigner).balanceOf(wstethSigner));
    console.log('wst eth amount %s', await wsteth.connect(wstethSigner).balanceOf(wstethSigner));
  });

  it.skip("swap 2eth to usdc%", async function () {
    console.log("-------------swap eth to usd---------------");
    const ethSigner = await ethers.getImpersonatedSigner(
        "0x891af9013e202eea5ef1e14e32de01488f579b65"
      );

    await weth
      .connect(ethSigner)
      .approve(await camelotSwapContract.getAddress(), BigInt(100*1e18));
     
    console.log('----Before swap----');
    console.log('eth amount %s', await weth.connect(ethSigner).balanceOf(ethSigner));
    console.log('usdc amount %s', await usdc.connect(ethSigner).balanceOf(ethSigner));
    const swapEthToUsdcTx = await camelotSwapContract
      .connect(ethSigner)
      .swapTo(ethSigner, weth, BigInt(2*1e18), usdc);
      await swapEthToUsdcTx.wait();
    console.log('----After swap----');
    console.log('eth amount %s', await weth.connect(ethSigner).balanceOf(ethSigner));
    console.log('usdc amount %s', await wsteth.connect(ethSigner).balanceOf(ethSigner));
  });

  it.skip("swap 2usdc to eth%", async function () {
    console.log("-------------swap usd to eth---------------");
    const usdSigner = await ethers.getImpersonatedSigner(
        "0x1714400ff23db4af24f9fd64e7039e6597f18c2b"
      );

    await usdc
      .connect(usdSigner)
      .approve(await camelotSwapContract.getAddress(), BigInt(100*1e18));
     
    console.log('----Before swap----');
    console.log('usdc amount %s', await usdc.connect(usdSigner).balanceOf(usdSigner));
    console.log('eth amount %s', await weth.connect(usdSigner).balanceOf(usdSigner));
    const swapUsdcToEthTx = await camelotSwapContract
      .connect(usdSigner)
      .swapTo(usdSigner, usdc, BigInt(2*1e6), weth);
      await swapUsdcToEthTx.wait();
    console.log('----After swap----');
    console.log('usdc amount %s', await usdc.connect(usdSigner).balanceOf(usdSigner));
    console.log('eth amount %s', await weth.connect(usdSigner).balanceOf(usdSigner));
  });

  it.skip("swap 2usdc to eth using swapToWithOutput%", async function () {
    console.log("-------------swap eth to usd---------------");
    const usdSigner = await ethers.getImpersonatedSigner(
        "0x1714400ff23db4af24f9fd64e7039e6597f18c2b"
      );

    await usdc
      .connect(usdSigner)
      .approve(await camelotSwapContract.getAddress(), BigInt(100*1e18));
     
    console.log('----Before swap----');
    console.log('usdc amount %s', await usdc.connect(usdSigner).balanceOf(usdSigner));
    console.log('eth amount %s', await weth.connect(usdSigner).balanceOf(usdSigner));
    const swapUsdcToEthTx = await camelotSwapContract
      .connect(usdSigner)
      .swapToWithOutput(usdSigner, usdc, BigInt(0.05*1e18), weth);
      await swapUsdcToEthTx.wait();
    console.log('----After swap----');
    console.log('usdc amount %s', await usdc.connect(usdSigner).balanceOf(usdSigner));
    console.log('eth amount %s', await weth.connect(usdSigner).balanceOf(usdSigner));
  });

  it("get token price price consumer", async function () {
    console.log("-------------get token price price consumer---------------");
    const contractAdmin = await ethers.getImpersonatedSigner("0xAD38f5DD867EF07B8Fe7dF685F28743922Bb33C4");
    const priceFeedContract = await ethers.getContractAt("PriceConsumer", "0x17FaBB6235383094938d250C4472308Ab1A70F40");

    let priceFeed = await priceFeedContract.connect(contractAdmin).getPriceOf(wethAddress, usdcAddress);
    console.log("wethAddress-usdcAddress:",priceFeed);
    priceFeed = await priceFeedContract.connect(contractAdmin).getPriceOf(wstethAddress, wethAddress);
    console.log("wstethAddress-wethAddress:",priceFeed);
    priceFeed = await priceFeedContract.connect(contractAdmin).getPriceOf(usdceAddress, usdcAddress);
    console.log("usdceAddress-usdcAddress:",priceFeed);
    priceFeed = await priceFeedContract.connect(contractAdmin).getPriceOf(arbAddress, usdcAddress);
    console.log("arbAddress-usdcAddress:",priceFeed);
    priceFeed = await priceFeedContract.connect(contractAdmin).getPriceOf(ezEthAddress, wethAddress);
    console.log("ezEthAddress-wethAddress:",priceFeed);
    priceFeed = await priceFeedContract.connect(contractAdmin).getPriceOf(rsEthAddress, wethAddress);
    console.log("rsEthAddress-wethAddress:",priceFeed);
    priceFeed = await priceFeedContract.connect(contractAdmin).getPriceOf(usdtAddress, usdcAddress);
    console.log("usdtAddress-usdcAddress:",priceFeed);
    priceFeed = await priceFeedContract.connect(contractAdmin).getPriceOf(daiAddress, usdtAddress);
    console.log("daiAddress-usdtAddress:",priceFeed);
    console.log("-------------Update price feed---------------");
    const newPF = '0xF4b7Fd2E7906016F685312Ec4961c58F2920a304';
    const tx = await priceFeedContract.connect(contractAdmin).updatePriceFeed(usdceAddress, usdcAddress, newPF);
    priceFeed = await priceFeedContract.connect(contractAdmin).getPriceOf(usdceAddress, usdcAddress);
    console.log("usdceAddress-usdcAddress:",priceFeed);
  });
});