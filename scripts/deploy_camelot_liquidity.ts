// Note: Should update priceConsumerAddress and redeploy camelotSwapContract before deploy the vault in next release
import { ethers, network } from "hardhat";

import {
    CHAINID,
    NonfungiblePositionManager
  } from "../constants";
import * as Contracts from "../typechain-types";

const chainId: CHAINID = network.config.chainId ?? 0;
console.log("chainId ",chainId);

const nonfungiblePositionManager = NonfungiblePositionManager[chainId] ?? "";

async function deployCamelotLiquidityContract() {
    const factory = await ethers.getContractFactory("CamelotLiquidity");
    const camelotLiquidityContract = (await factory.deploy(
      nonfungiblePositionManager,
      {
        gasLimit: 100988531,
      }
    )) as Contracts.CamelotLiquidity;
    const camelotLiquidityAddress = await camelotLiquidityContract.getAddress();
  
    console.log(
      "Deployed Camelot LP contract at address %s",
      camelotLiquidityAddress
    );
  
    return camelotLiquidityAddress;
  }

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account: ", await deployer.getAddress());

  await deployCamelotLiquidityContract();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
