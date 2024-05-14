import { ethers } from "hardhat";
import * as Contracts from "../typechain-types";
import { Signer } from "ethers";

import {
  CHAINID,
  WETH_ADDRESS,
  USDC_ADDRESS,
  USDCE_ADDRESS,
  WSTETH_ADDRESS,
  ARB_ADDRESS,
  ETH_PRICE_FEED_ADDRESS,
  WSTETH_ETH_PRICE_FEED_ADDRESS,
  USDC_PRICE_FEED_ADDRESS,
  ARB_PRICE_FEED_ADDRESS
} from "../constants";

// const chainId: CHAINID = network.config.chainId;
const chainId: CHAINID = 42161;

let deployer: Signer;
let contract: Contracts.PriceConsumer;

const wethAddress = WETH_ADDRESS[chainId] ?? '';
const wstethAddress = WSTETH_ADDRESS[chainId] ?? '';
const usdceAddress = USDCE_ADDRESS[chainId] ?? '';
const usdcAddress = USDC_ADDRESS[chainId] ?? '';
const arbAddress = ARB_ADDRESS[chainId] ?? '';

const ethPriceFeed = ETH_PRICE_FEED_ADDRESS[chainId] ?? '';
const steth_ethPriceFeed = WSTETH_ETH_PRICE_FEED_ADDRESS[chainId] ?? '';
const usdcePriceFeed = USDC_PRICE_FEED_ADDRESS[chainId] ?? '';
const arbPriceFeed = ARB_PRICE_FEED_ADDRESS[chainId] ?? '';

async function deployPriceConsumerContract() {
    const factory = await ethers.getContractFactory("PriceConsumer");
    contract = await factory.deploy(
      [wethAddress, wstethAddress, usdceAddress, arbAddress],
      [usdcAddress, wethAddress, usdcAddress, usdcAddress],
      [ethPriceFeed, steth_ethPriceFeed, usdcePriceFeed, arbPriceFeed]
    );
    await contract.waitForDeployment();

    console.log(
      "Deployed price consumer contract at address %s",
      await contract.getAddress()
    );
  }
async function main() {
  [deployer] = await ethers.getSigners();
  console.log(
    "Deploying contracts with the account:",
    await deployer.getAddress()
  );

  deployPriceConsumerContract();
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
