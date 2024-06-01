const { ethers, network } = require("hardhat");
import axios from "axios";

import * as Contracts from "../typechain-types";
import {
    USDC_ADDRESS,
    USDCE_ADDRESS,
    CHAINID
} from "../constants";

const chainId: CHAINID = network.config.chainId;
const privateKey = process.env.PRIVATE_KEY || "";

const usdceAddress = USDCE_ADDRESS[chainId] ?? "";
  const usdcAddress = USDC_ADDRESS[chainId] ?? "";

async function main() {
    console.log('-------------load price feed---------------');
    const contractAdmin = new ethers.Wallet(privateKey, ethers.provider);
    console.log("contractAdmin %s", await contractAdmin.getAddress());

    const priceFeedContract = await ethers.getContractAt("PriceConsumer", "0x17FaBB6235383094938d250C4472308Ab1A70F40");
    let priceFeed = await priceFeedContract.connect(contractAdmin).getPriceOf(usdceAddress, usdcAddress);
    console.log("usdceAddress-usdcAddress:",priceFeed);

    console.log("-------------Update price feed---------------");
    const pfAddress = '0x4392c8D194C074A98034BB66A1235f9a3B24AC12';
    await priceFeedContract.connect(contractAdmin).updatePriceFeed(usdceAddress, usdcAddress, pfAddress);
    priceFeed = await priceFeedContract.connect(contractAdmin).getPriceOf(usdceAddress, usdcAddress);
    console.log("usdceAddress-usdcAddress:",priceFeed);

  }
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
  