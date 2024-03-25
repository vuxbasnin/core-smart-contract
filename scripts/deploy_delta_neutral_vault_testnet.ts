import { ethers, network } from "hardhat";

import {
  CHAINID,
  WETH_ADDRESS,
  WSTETH_ADDRESS,
  AEVO_ADDRESS,
  AEVO_CONNECTOR_ADDRESS,
} from "../constants";
import * as Contracts from "../typechain-types";

const chainId: CHAINID = network.config.chainId ?? 0;
console.log(chainId);

const wstethAddress = WSTETH_ADDRESS[chainId] ?? "";
const wethAddress = WETH_ADDRESS[chainId] ?? "";
const aevoAddress = AEVO_ADDRESS[chainId] ?? "";
const aevoConnectorAddress = AEVO_CONNECTOR_ADDRESS[chainId] ?? "";

let rockOnyxDeltaNeutralVaultContract: Contracts.RockOnyxDeltaNeutralVault;

async function deployCamelotSwapContract() {
  // Get the Contract Factory
  const MockSwapRouter = await ethers.getContractFactory("MockSwapRouter");

  // Deploy the Contract
  const swapRouter = await MockSwapRouter.deploy();
  console.log("Deployed SwapRouter %s", await swapRouter.getAddress());


  const factory = await ethers.getContractFactory("RockOnyxSwap");
  const camelotSwapContract = await factory.deploy(
    await swapRouter.getAddress()
  );
  await camelotSwapContract.waitForDeployment();
  
  console.log(
    "Deployed Camelot Swap contract at address %s",
    await camelotSwapContract.getAddress()
  );

  return await camelotSwapContract.getAddress();
}

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log(
    "Deploying contracts with the account:",
    await deployer.getAddress()
  );

  const camelotSwapAddress = await deployCamelotSwapContract();

  const usdcAddress = "0xA33a482E2e470E2d1286d0e791923657F59428f2";
  const optionsTrader = "0x0aDf03D895617a95F317892125Cd6fb9ca3b99c1";

  const rockOnyxDeltaNeutralVault = await ethers.getContractFactory(
    "RockOnyxDeltaNeutralVault"
  );

  rockOnyxDeltaNeutralVaultContract = await rockOnyxDeltaNeutralVault.deploy(
    usdcAddress,
    camelotSwapAddress,
    "",
    optionsTrader,
    wethAddress,
    wstethAddress
  );
  await rockOnyxDeltaNeutralVaultContract.waitForDeployment();

  console.log(
    "deploy rockOnyxDeltaNeutralVaultContract successfully: %s",
    await rockOnyxDeltaNeutralVaultContract.getAddress()
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
