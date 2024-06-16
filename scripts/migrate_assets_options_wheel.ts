import { ethers, network } from "hardhat";
import { CHAINID, USDC_ADDRESS } from "../constants";

async function main() {
  const chainId: CHAINID = network.config.chainId || 0;
  console.log("chainId", chainId);
  const privateKey = process.env.PRIVATE_KEY || "";
  const oldPrivateKey = process.env.OLD_PRIVATE_KEY || "";
  const usdcAddress = USDC_ADDRESS[chainId];

  const oldAdmin = new ethers.Wallet(oldPrivateKey, ethers.provider);
  const oldVaultAddress = "0x0bD37D11e3A25B5BB0df366878b5D3f018c1B24c";
  const oldContract = await ethers.getContractAt(
    "RockOnyxUSDTVault",
    oldVaultAddress
  );

  const newVaultAddress = "0x316CDbBEd9342A1109D967543F81FA6288eBC47D";

  // Connect to the USDC contract
  const usdcContract = await ethers.getContractAt("IERC20", usdcAddress);

  const totalWithdrawAmount = await usdcContract.balanceOf(
    await oldContract.getAddress()
  );
  console.log(
    "USDC balance of %s %s",
    await oldContract.getAddress(),
    totalWithdrawAmount
  );

  console.log("-------------emergencyShutdown---------------");

  await oldContract
    .connect(oldAdmin)
    .emergencyShutdown(newVaultAddress, usdcAddress, totalWithdrawAmount);

  const newVaultBalance = await usdcContract.balanceOf(newVaultAddress);
  console.log("USDC balance of newVaultAddress: %s", newVaultBalance);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
