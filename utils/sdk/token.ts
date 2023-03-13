import { parseEther } from 'ethers/lib/utils';
import { BigNumber } from 'ethers';
import { OrderType } from './types';

const MIN_TICK_DISTANCE = parseEther('0.001');

export interface TokenIdParams {
  version: number;
  orderType: OrderType;
  operator: string;
  upper: BigNumber;
  lower: BigNumber;
}

export function formatTokenId({
  version,
  orderType,
  operator,
  upper,
  lower,
}: TokenIdParams) {
  let tokenId = BigNumber.from(version).shl(252);
  tokenId = tokenId.add(BigNumber.from(orderType.valueOf()).shl(180));
  tokenId = tokenId.add(BigNumber.from(operator).shl(20));
  tokenId = tokenId.add(upper.div(MIN_TICK_DISTANCE).shl(10));
  tokenId = tokenId.add(lower.div(MIN_TICK_DISTANCE));

  return tokenId;
}

export function parseTokenId(tokenId: BigNumber): TokenIdParams {
  return {
    version: tokenId.shr(252).toNumber(),
    orderType: tokenId
      .shr(180)
      .and('0xf') // 4 bits mask
      .toNumber(),
    operator: tokenId
      .shr(20)
      .and('0x' + 'ff'.repeat(20)) // 20 bits mask
      .toHexString(),
    upper: tokenId
      .shr(10)
      .and('0x3ff') // 10 bits mask
      .mul(MIN_TICK_DISTANCE),
    lower: tokenId
      .and('0x3ff') // 10 bits mask
      .mul(MIN_TICK_DISTANCE),
  };
}
