import { ethers, network } from "hardhat";
import * as Contracts from "../typechain-types";
import { Signer } from "ethers";
import {
  CHAINID,
  USDC_ADDRESS,
  NonfungiblePositionManager,
  SWAP_ROUTER_ADDRESS,
  AEVO_ADDRESS,
  AEVO_CONNECTOR_ADDRESS,
  USDCE_ADDRESS,
  WSTETH_ADDRESS,
  WETH_ADDRESS,
  AEVO_TRADER_ADDRESS,
} from "../constants";

const chainId: CHAINID = network.config.chainId ?? 0;

// assets
const usdcAddress = USDC_ADDRESS[chainId] ?? "";
const usdceAddress = USDCE_ADDRESS[chainId] ?? "";
const wstethAddress = WSTETH_ADDRESS[chainId] ?? "";
const wethAddress = WETH_ADDRESS[chainId] ?? "";
const nonfungiblePositionManager = NonfungiblePositionManager[chainId] ?? "";
let deployer: Signer;

const GAS_LIMIT = 50988531;

async function deployLiquidityContract() {
  const factory = await ethers.getContractFactory("CamelotLiquidity");
  const camelotLiquidityContract = (await factory.deploy(
    nonfungiblePositionManager,
    {
      gasLimit: GAS_LIMIT,
    }
  )) as Contracts.CamelotLiquidity;
  const camelotLiquidityAddress = await camelotLiquidityContract.getAddress();

  console.log(
    "Deployed Camelot LP contract at address %s",
    camelotLiquidityAddress
  );

  return camelotLiquidityAddress;
}

async function deployCamelotSwapContract() {
  // Deploy the Contract
  const swapRouterAddress = SWAP_ROUTER_ADDRESS[chainId] ?? "";
  console.log("SwapRouter %s", swapRouterAddress);

  const factory = await ethers.getContractFactory("CamelotSwap");
  const camelotSwapContract = await factory.deploy(swapRouterAddress, {
    gasLimit: GAS_LIMIT,
  });
  await camelotSwapContract.waitForDeployment();

  console.log(
    "Deployed Camelot Swap contract at address %s",
    await camelotSwapContract.getAddress()
  );

  return await camelotSwapContract.getAddress();
}

async function deployAevoContract() {
  const aevoOptionsAddress = AEVO_ADDRESS[chainId] ?? "";
  const aevoConnectorAddress = AEVO_CONNECTOR_ADDRESS[chainId] ?? "";

  const factory = await ethers.getContractFactory("AevoOptions");
  const aevoOptionsContract = (await factory.deploy(
    usdceAddress,
    aevoOptionsAddress,
    aevoConnectorAddress,
    {
      gasLimit: GAS_LIMIT,
    }
  )) as Contracts.AevoOptions;
  const aevoProxyAddress = await aevoOptionsContract.getAddress();
  console.log("Deployed AEVO contract at address %s", aevoProxyAddress);

  return aevoProxyAddress;
}

async function main() {
  [deployer] = await ethers.getSigners();
  console.log(
    "Deploying contracts with the account:",
    await deployer.getAddress()
  );

  // const camelotLiquidityAddress = await deployLiquidityContract();
  // const camelotSwapAddress = await deployCamelotSwapContract();
  // const aevoProxyAddress = await deployAevoContract();

  const camelotLiquidityAddress = "0x05AAe168AEB8516a068D9DED91F56f81C76706Eb";
  const camelotSwapAddress = "0x7EA2362e578212d7FDA082E0bBB5134f89EDc4DC";
  const aevoProxyAddress = "0xd6d7a2557DE8d91AD6F22AbDAe32BCE226dAE68d";

  const RockOnyxUSDTVaultFactory = await ethers.getContractFactory(
    "RockOnyxUSDTVault"
  );
  const rockOnyxUSDTVault = await RockOnyxUSDTVaultFactory.deploy(
    usdcAddress,
    camelotLiquidityAddress,
    nonfungiblePositionManager,
    camelotSwapAddress,
    aevoProxyAddress,
    AEVO_TRADER_ADDRESS[chainId] ?? "",
    usdceAddress,
    wethAddress,
    wstethAddress,
    {
      gasLimit: GAS_LIMIT,
    }
  );

  console.log(
    "Deployed rockOnyxUSDTVault at address %s",
    await rockOnyxUSDTVault.getAddress()
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
