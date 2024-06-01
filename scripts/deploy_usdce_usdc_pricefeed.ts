// Note: Should update priceConsumerAddress and redeploy camelotSwapContract before deploy the vault in next release
import { ethers } from "hardhat";
import * as Contracts from "../typechain-types";
import { Signer } from "ethers";

let deployer: Signer;
let contract: Contracts.UsdceUsdcPriceFeedOracle;

async function UsdceUsdcPriceFeedOracle() {
  const factory = await ethers.getContractFactory("UsdceUsdcPriceFeedOracle");
  contract = await factory.deploy(1*1e8, 8);

  await contract.waitForDeployment(); 

  console.log(
    "Deployed usdceUsdc pricefeed oracle at address %s",
    await contract.getAddress()
  );
}

async function main() {
  [deployer] = await ethers.getSigners();
  console.log(
    "Deploying contracts with the account:",
    await deployer.getAddress()
  );

  UsdceUsdcPriceFeedOracle();
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
