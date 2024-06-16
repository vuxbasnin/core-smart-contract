import { ethers, network } from "hardhat";
import { CHAINID, RSETH_ADDRESS, USDC_ADDRESS } from "../constants";

async function main() {
  const chainId: CHAINID = network.config.chainId || 0;
  console.log("chainId", chainId);
  const privateKey = process.env.PRIVATE_KEY || "";
  const oldPrivateKey = process.env.OLD_PRIVATE_KEY || "";
  const usdcAddress = USDC_ADDRESS[chainId];
  const rsETHAddress = RSETH_ADDRESS[chainId];

  const oldAdmin = new ethers.Wallet(oldPrivateKey, ethers.provider);
  const oldVaultAddress = "0x2B7cDAD36a86fd05Ac1680CDc42a0EA16804D80c";
  const oldContract = await ethers.getContractAt(
    "KelpRestakingDeltaNeutralVault",
    oldVaultAddress
  );

  const newVaultAddress = "0xF30353335003E71b42a89314AAaeC437E7Bc8F0B";

  // Connect to the USDC contract
  const usdcContract = await ethers.getContractAt("IERC20", usdcAddress);
  const rsEthContract = await ethers.getContractAt("IERC20", rsETHAddress);


  console.log("-------------Transfer USDC ---------------");
  const totalUSDC = await usdcContract.balanceOf(
    await oldContract.getAddress()
  );
  console.log(
    "USDC balance of %s %s",
    await oldContract.getAddress(),
    totalUSDC
  );

  await oldContract
    .connect(oldAdmin)
    .emergencyShutdown(newVaultAddress, usdcAddress, totalUSDC);

  let newVaultBalance = await usdcContract.balanceOf(newVaultAddress);
  console.log("USDC balance of newVaultAddress: %s", newVaultBalance);

  const totalRsEth = await rsEthContract.balanceOf(
    await oldContract.getAddress()
  );
  console.log(
    "rsETH balance of %s %s",
    await oldContract.getAddress(),
    totalRsEth
  );

  console.log("-------------Transfer rsETH ---------------");

  await oldContract
    .connect(oldAdmin)
    .emergencyShutdown(newVaultAddress, rsETHAddress, totalRsEth);

  newVaultBalance = await rsEthContract.balanceOf(newVaultAddress);
  console.log("rsETH balance of newVaultAddress: %s", newVaultBalance);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
