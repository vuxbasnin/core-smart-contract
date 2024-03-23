import { ethers } from "hardhat";
import * as Contracts from "../../typechain-types";
import { Signer } from "ethers";

export async function transferIERC20FundForUser(
  asset: Contracts.IERC20,
  from: string,
  to: Signer,
  amount: number
) {
  const impersonatedSigner = await ethers.getImpersonatedSigner(from);
  const recipientAddress = await to.getAddress();

  console.log(
    "balance of impersonatedSigner",
    await asset
      .connect(impersonatedSigner)
      .balanceOf(await impersonatedSigner.getAddress())
  );

  const transferTx = await asset
    .connect(impersonatedSigner)
    .transfer(recipientAddress, ethers.parseUnits(amount.toString(), 6));
  await transferTx.wait();

  const balanceOfUser = await asset.connect(to).balanceOf(recipientAddress);
  console.log("Balance of user %s", balanceOfUser);
}
