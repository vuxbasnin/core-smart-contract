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

const GAS_LIMIT = 11988531;

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

  const camelotLiquidityAddress = await deployLiquidityContract();
  const camelotSwapAddress = await deployCamelotSwapContract();
  const aevoProxyAddress = await deployAevoContract();

  // const camelotLiquidityAddress = "0xe22edc2f94857F9a4703fb85793ebd69762aF596";
  // const camelotSwapAddress = "0x527B821B7eadC2Ea01c9BD3dFd8a99f025B15203";
  // const aevoProxyAddress = "0xF15e8c271a77D8A6F0B4B5D1345BcC83355Cf150";

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
