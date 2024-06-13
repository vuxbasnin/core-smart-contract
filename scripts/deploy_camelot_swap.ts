// Note: Should update priceConsumerAddress and redeploy camelotSwapContract before deploy the vault in next release
import { ethers, network } from "hardhat";

import {
    CHAINID,
    SWAP_ROUTER_ADDRESS,
    PRICE_CONSUMER_ADDRESS
} from "../constants";
import * as Contracts from "../typechain-types";

const chainId: CHAINID = network.config.chainId ?? 0;
console.log("chainId ",chainId);

const swapRouterAddress = SWAP_ROUTER_ADDRESS[chainId] || "";
const priceConsumerAddress = PRICE_CONSUMER_ADDRESS[chainId] || "";
const admin = '0xad38f5dd867ef07b8fe7df685f28743922bb33c4';
let camelotContract: Contracts.CamelotSwap;

async function deployUniSwapContract() {
    const factory = await ethers.getContractFactory("CamelotSwap");
    camelotContract = await factory.deploy(
      admin,
      swapRouterAddress,
      priceConsumerAddress
    );
    await camelotContract.waitForDeployment();

    console.log(
      "Deployed camelot contract at address %s",
      await camelotContract.getAddress()
    );
}


async function main() {
  const [deployer] = await ethers.getSigners();

  console.log(
    "Deploying contracts with the account:",
    await deployer.getAddress()
  );

  await deployUniSwapContract();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
