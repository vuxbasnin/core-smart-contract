const { ethers } = require("hardhat");

import * as Contracts from "../../typechain-types";
import {
  CHAINID,
  WETH_ADDRESS,
  USDC_ADDRESS,
  SWAP_ROUTER_ADDRESS,
  ETH_PRICE_FEED_ADDRESS,
  EZETH_ADDRESS,
  EZETH_ETH_PRICE_FEED_ADDRESS,
} from "../../constants";
import { network } from "hardhat";
import {
  Signer,
} from "ethers";

const chainId: CHAINID = network.config.chainId as CHAINID;
console.log("chainId", chainId);

describe("UniSwap", function () {
  let admin: Signer;
  let priceConsumerContract: Contracts.PriceConsumer;
  let USDC: Contracts.IERC20;
  let EZETH: Contracts.IERC20;
  let WETH: Contracts.IERC20;

  const usdcAddress = USDC_ADDRESS[chainId];
  const ezEthAddress = EZETH_ADDRESS[chainId];
  const wethAddress = WETH_ADDRESS[chainId];
  const swapRouterAddress = SWAP_ROUTER_ADDRESS[chainId];

  const ethPriceFeed = ETH_PRICE_FEED_ADDRESS[chainId];
  const ezEth_ethPriceFeed = EZETH_ETH_PRICE_FEED_ADDRESS[chainId];

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
      await priceConsumerContract.getAddress()
    );
    await uniswapContract.waitForDeployment();

    console.log(
      "Deployed Uniswap contract at address %s",
      await uniswapContract.getAddress()
    );
  }

  beforeEach(async function () {
    console.log("usdcAddress %s", usdcAddress);
    console.log("ezEthAddress %s", ezEthAddress);
    console.log("wethAddress %s", wethAddress);
    [admin] = await ethers.getSigners();

    USDC = await ethers.getContractAt("IERC20", usdcAddress);
    EZETH = await ethers.getContractAt("IERC20", ezEthAddress);
    WETH = await ethers.getContractAt("IERC20", wethAddress);

    await deployPriceConsumerContract();
    await deployUniswapContract();
  });

  it.skip("get token price", async function () {
      console.log("-------------get weth_usd price feed---------------");
      const getEth_UsdPrice = await uniswapContract
        .connect(admin)
        .getPriceOf(WETH, USDC);
        console.log('1 WETH = %s USDC', getEth_UsdPrice);
    
      console.log("-------------get usd_eth price feed---------------");
      const getUsd_EthPrice = await uniswapContract
        .connect(admin)
        .getPriceOf(USDC, WETH);
        console.log('1 USDC = %s WETH', getUsd_EthPrice);

      console.log("-------------get ezeht_weth price feed---------------");
      const getEzEth_EthPrice = await uniswapContract
        .connect(admin)
        .getPriceOf(EZETH, WETH);
        console.log('1 EZETH = %s WETH', getEzEth_EthPrice);
    
      console.log("-------------get weth_ezeth price feed---------------");
      const getEth_EzEthPrice = await uniswapContract
        .connect(admin)
        .getPriceOf(WETH, EZETH);
        console.log('1 WETH = %s EZETH', getEth_EzEthPrice);
  });

  it.skip("swap 2usdc to weth", async function () {
    console.log("-------------swap 2usdc to weth---------------");
    const usdSigner = await ethers.getImpersonatedSigner(
        "0x95b8E28F8A2B24b5683bdc09924E6926D3F5f8D3"
      );

    await USDC
      .connect(usdSigner)
      .approve(await uniswapContract.getAddress(), await USDC.connect(usdSigner).balanceOf(usdSigner));
    
    console.log('----Before swap----');
    console.log('usdc amount %s', await USDC.connect(usdSigner).balanceOf(usdSigner));
    console.log('eth amount %s', await WETH.connect(usdSigner).balanceOf(usdSigner));
    const swapUsdcToEthTx = await uniswapContract
      .connect(usdSigner)
      .swapTo(usdSigner, USDC, BigInt(2*1e6), WETH, 100);
      await swapUsdcToEthTx.wait();
    console.log('----After swap----');
    console.log('usdc amount %s', await USDC.connect(usdSigner).balanceOf(usdSigner));
    console.log('eth amount %s', await WETH.connect(usdSigner).balanceOf(usdSigner));
  });

  it("swap usdc to 0.05eth using swapToWithOutput", async function () {
    console.log("-------------swap 2usdc to eth using swapToWithOutput---------------");
    const usdSigner = await ethers.getImpersonatedSigner(
        "0x95b8E28F8A2B24b5683bdc09924E6926D3F5f8D3"
      );

    await USDC
      .connect(usdSigner)
      .approve(await uniswapContract.getAddress(), await USDC.connect(usdSigner).balanceOf(usdSigner));
    
    console.log('----Before swap----');
    console.log('usdc amount %s', await USDC.connect(usdSigner).balanceOf(usdSigner));
    console.log('eth amount %s', await WETH.connect(usdSigner).balanceOf(usdSigner));
    const usdbf = await USDC.connect(usdSigner).balanceOf(usdSigner);

    const swapUsdcToEthTx = await uniswapContract
      .connect(usdSigner)
      .swapToWithOutput(usdSigner, USDC, BigInt(0.02*1e18), WETH, 500);
      await swapUsdcToEthTx.wait();
    console.log('----After swap----');
    console.log('usdc amount %s', await USDC.connect(usdSigner).balanceOf(usdSigner));
    console.log('eth amount %s', await WETH.connect(usdSigner).balanceOf(usdSigner));

    const usdAmount = await uniswapContract.getAmountInMaximum(USDC, WETH, BigInt(0.05*1e18));
    console.log('usd getAmountInMaximum %s', usdAmount);
    console.log('ussed amount %s', usdbf - await USDC.connect(usdSigner).balanceOf(usdSigner));
  });

  it.skip("swap 2eth to usdc", async function () {
    console.log("-------------swap eth to usd---------------");
    const ethSigner = await ethers.getImpersonatedSigner(
        "0x274d9e726844ab52e351e8f1272e7fc3f58b7e5f"
      );

    await WETH
      .connect(ethSigner)
      .approve(await uniswapContract.getAddress(), BigInt(100*1e18));
    console.log('----Before swap----');
    console.log('eth amount %s', await WETH.connect(ethSigner).balanceOf(ethSigner));
    console.log('usdc amount %s', await USDC.connect(ethSigner).balanceOf(ethSigner));
    const swapEthToUsdcTx = await uniswapContract
      .connect(ethSigner)
      .swapTo(ethSigner, WETH, BigInt(2*1e18), USDC, 500);
      await swapEthToUsdcTx.wait();
    console.log('----After swap----');
    console.log('eth amount %s', await WETH.connect(ethSigner).balanceOf(ethSigner));
    console.log('usdc amount %s', await USDC.connect(ethSigner).balanceOf(ethSigner));
  });

  it.skip("swap 2eth to ezeth %", async function () {
    console.log("-------------swap eth to usd---------------");
    const ethSigner = await ethers.getImpersonatedSigner(
        "0x274d9e726844ab52e351e8f1272e7fc3f58b7e5f"
      );

    await WETH
      .connect(ethSigner)
      .approve(await uniswapContract.getAddress(), BigInt(100*1e18));
     
    console.log('----Before swap----');
    console.log('eth amount %s', await WETH.connect(ethSigner).balanceOf(ethSigner));
    console.log('ezeth amount %s', await EZETH.connect(ethSigner).balanceOf(ethSigner));
    const swapEthToEzEthTx = await uniswapContract
      .connect(ethSigner)
      .swapTo(ethSigner, WETH, BigInt(2*1e18), EZETH, 100);
      await swapEthToEzEthTx.wait();
    console.log('----After swap----');
    console.log('eth amount %s', await WETH.connect(ethSigner).balanceOf(ethSigner));
    console.log('ezeth amount %s', await EZETH.connect(ethSigner).balanceOf(ethSigner));
  });

  it.skip("swap ezeth to 0.05eth using swapToWithOutput", async function () {
    console.log("-------------swap ezeth to 0.05eth using swapToWithOutput---------------");
    const ezethSigner = await ethers.getImpersonatedSigner(
        "0x40f18Fe2858063dD680093014E11C126FDd2533a"
      );

    await EZETH
      .connect(ezethSigner)
      .approve(await uniswapContract.getAddress(), BigInt(100*1e18));
     
    console.log('----Before swap----');
    console.log('eth amount %s', await WETH.connect(ezethSigner).balanceOf(ezethSigner));
    console.log('ezeth amount %s', await EZETH.connect(ezethSigner).balanceOf(ezethSigner));
    const swapEzEthToEthTx = await uniswapContract
      .connect(ezethSigner)
      .swapToWithOutput(ezethSigner, EZETH, BigInt(0.05*1e18), WETH, 100);
      await swapEzEthToEthTx.wait();
    console.log('----After swap----');
    console.log('eth amount %s', await WETH.connect(ezethSigner).balanceOf(ezethSigner));
    console.log('ezeth amount %s', await EZETH.connect(ezethSigner).balanceOf(ezethSigner));
  });

  it.skip("swap usdc to usd, arb mainnet", async function () {
    console.log("-------------swap usdc to usd, arb mainnet---------------");
    const ezethSigner = await ethers.getImpersonatedSigner(
        "0x7354F8aDFDfc6ca4D9F81Fc20d04eb8A7b11b01b"
      );

    await USDC
      .connect(ezethSigner)
      .approve(await uniswapContract.getAddress(), BigInt(100*1e18));
     
    console.log('----Before swap----');
    console.log('eth amount %s', await WETH.connect(ezethSigner).balanceOf(ezethSigner));
    console.log('ezeth amount %s', await EZETH.connect(ezethSigner).balanceOf(ezethSigner));
    const swapEzEthToEthTx = await uniswapContract
      .connect(ezethSigner)
      .swapToWithOutput(ezethSigner, EZETH, BigInt(0.05*1e18), WETH, 100);
      await swapEzEthToEthTx.wait();
    console.log('----After swap----');
    console.log('eth amount %s', await WETH.connect(ezethSigner).balanceOf(ezethSigner));
    console.log('ezeth amount %s', await EZETH.connect(ezethSigner).balanceOf(ezethSigner));
  });
});
