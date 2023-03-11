import { BigNumber } from 'ethers';
import { formatEther, formatUnits, parseUnits } from 'ethers/lib/utils';

export function average(a: BigNumber, b: BigNumber): BigNumber {
  return a.add(b).div(2);
}

export function bnToNumber(bn: BigNumber, decimals = 18) {
  return Number(formatUnits(bn, decimals));
}

export function scaleDecimals(bn: BigNumber, decimals: number) {
  return parseUnits(formatEther(bn), decimals);
}
