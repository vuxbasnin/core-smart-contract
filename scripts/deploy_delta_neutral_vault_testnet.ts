import { ethers, network } from "hardhat";

import {
  CHAINID,
  WETH_ADDRESS,
  USDC_ADDRESS,
  WSTETH_ADDRESS,
  SWAP_ROUTER_ADDRESS,
  AEVO_V2_ADDRESS,
  AEVO_CONNECTOR_V2_ADDRESS,
} from "../constants";
import * as Contracts from "../typechain-types";

const chainId: CHAINID = network.config.chainId ?? 0;
console.log(chainId);

const wstethAddress = WSTETH_ADDRESS[chainId];
const wethAddress = WETH_ADDRESS[chainId];
const aevoAddress = AEVO_V2_ADDRESS[chainId];
const aevoConnectorAddress = AEVO_CONNECTOR_V2_ADDRESS[chainId];

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

  const optionsTrader = "0x0aDf03D895617a95F317892125Cd6fb9ca3b99c1";

  const rockOnyxDeltaNeutralVault = await ethers.getContractFactory(
    "RockOnyxDeltaNeutralVault"
  );

  const usdcAddress = "0xA33a482E2e470E2d1286d0e791923657F59428f2";

  rockOnyxDeltaNeutralVaultContract = await rockOnyxDeltaNeutralVault.deploy(
    usdcAddress,
    camelotSwapAddress,
    "0x802c037f1Fed29A91263A7CFe8D877c82C9A42A6", // mock
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
