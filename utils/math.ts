import { BigNumber } from 'ethers';

export function average(a: BigNumber, b: BigNumber): BigNumber {
  return a.add(b).div(2);
}
