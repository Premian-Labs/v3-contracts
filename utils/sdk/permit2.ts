import { BigNumber, BigNumberish, BytesLike } from 'ethers';
import { randomBytes } from 'ethers/lib/utils';
import { PermitTransferFrom, SignatureTransfer } from '@uniswap/permit2-sdk';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

export const PERMIT2 = '0x000000000022D473030F116dDEE9F6B43aC78BA3';

export interface PremiaPermit2 {
  deadline: BigNumberish;
  nonce: BigNumberish;
  permittedAmount: BigNumberish;
  permittedToken: string;
  signature: BytesLike;
}

export function getRandomPermit2Nonce() {
  return BigNumber.from(randomBytes(32)).shr(8).shl(8).add(1);
}

export async function signPermit2(
  signer: SignerWithAddress,
  permit: PermitTransferFrom,
) {
  const chainId = (await signer.provider!.getNetwork()).chainId;

  const { domain, types, values } = SignatureTransfer.getPermitData(
    permit,
    PERMIT2,
    chainId,
  );

  return signer._signTypedData(domain, types, values);
}

export async function signPremiaPermit2(
  signer: SignerWithAddress,
  permit: PermitTransferFrom,
): Promise<PremiaPermit2> {
  return {
    deadline: permit.deadline,
    nonce: permit.nonce,
    permittedAmount: permit.permitted.amount,
    permittedToken: permit.permitted.token,
    signature: await signPermit2(signer, permit),
  };
}
