import { ethers, network } from "hardhat";

import {
  CHAINID,
  WETH_ADDRESS,
  USDC_ADDRESS,
  WSTETH_ADDRESS,
  AEVO_ADDRESS,
  AEVO_CONNECTOR_ADDRESS,
  SWAP_ROUTER_ADDRESS,
} from "../constants";
import * as Contracts from "../typechain-types";

const chainId: CHAINID = network.config.chainId ?? 0;

const usdcAddress = USDC_ADDRESS[chainId] ?? "";
const wstethAddress = WSTETH_ADDRESS[chainId] ?? "";
const wethAddress = WETH_ADDRESS[chainId] ?? "";
const aevoAddress = AEVO_ADDRESS[chainId] ?? "";
const aevoConnectorAddress = AEVO_CONNECTOR_ADDRESS[chainId] ?? "";

let aevoContract: Contracts.Aevo;
let rockOnyxDeltaNeutralVaultContract: Contracts.RockOnyxDeltaNeutralVault;

async function deployAevoContract() {
  const factory = await ethers.getContractFactory("Aevo");
  console.log(usdcAddress, aevoAddress, aevoConnectorAddress);

  aevoContract = await factory.deploy(
    usdcAddress,
    aevoAddress,
    aevoConnectorAddress
  );
  await aevoContract.waitForDeployment();

  console.log(
    "Deployed AEVO contract at address %s",
    await aevoContract.getAddress()
  );
}

let camelotSwapContract: Contracts.CamelotSwap;
const swapRouterAddress = SWAP_ROUTER_ADDRESS[chainId] || "";

async function deployCamelotSwapContract() {
  const factory = await ethers.getContractFactory("CamelotSwap");
  camelotSwapContract = await factory.deploy(swapRouterAddress);
  await camelotSwapContract.waitForDeployment();

  console.log(
    "Deployed Camelot Swap contract at address %s",
    await camelotSwapContract.getAddress()
  );
}

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log(
    "Deploying contracts with the account:",
    await deployer.getAddress()
  );
  await deployCamelotSwapContract();
  const camelotSwapAddress = await camelotSwapContract.getAddress();
  // const camelotSwapAddress = "0x7EA2362e578212d7FDA082E0bBB5134f89EDc4DC";

  const optionsTrader = "0x0aDf03D895617a95F317892125Cd6fb9ca3b99c1";

  // await deployAevoContract();

  const rockOnyxDeltaNeutralVault = await ethers.getContractFactory(
    "RockOnyxDeltaNeutralVault"
  );

  rockOnyxDeltaNeutralVaultContract = await rockOnyxDeltaNeutralVault.deploy(
    usdcAddress,
    camelotSwapAddress,
    // await aevoContract.getAddress(),
    "0x3D75e9366Fe5A2f1B7481a4Fb05deC21f8038467",
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
