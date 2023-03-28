import { Token, tokens } from './addresses';
import { latest } from './time';
import axios from 'axios';
import { expect } from 'chai';
import { BigNumber, utils } from 'ethers';

export const getLastPrice = async (
  network: string,
  coin: string,
): Promise<number> => {
  return await getPrice(network, coin);
};

export const getPrice = async (
  network: string,
  coin: string,
  timestamp?: number,
): Promise<number> => {
  const { price } = await getTokenData(network, coin, timestamp);
  return price;
};

export const getTokenData = async (
  network: string,
  coin: string,
  timestamp?: number,
): Promise<{ price: number; decimals: number }> => {
  const coinId = `${network}:${coin.toLowerCase()}`;
  const response = await axios.post('https://coins.llama.fi/prices', {
    coins: [coinId],
    timestamp,
  });

  const { coins } = response.data;

  return coins[coinId];
};

export const convertPriceToBigNumberWithDecimals = (
  price: number,
  decimals: number,
): BigNumber => {
  return utils.parseUnits(price.toFixed(decimals), decimals);
};

export const convertPriceToNumberWithDecimals = (
  price: number,
  decimals: number,
): number => {
  return convertPriceToBigNumberWithDecimals(price, decimals).toNumber();
};

export function validateQuote(
  percentage: number,
  quote: BigNumber,
  expected: BigNumber,
) {
  const threshold = expected.mul(percentage * 10).div(100 * 10);
  const [upperThreshold, lowerThreshold] = [
    expected.add(threshold),
    expected.sub(threshold),
  ];
  const diff = quote.sub(expected);
  const sign = diff.isNegative() ? '-' : '+';
  const diffPercentage = diff.abs().mul(10000).div(expected).toNumber() / 100;

  expect(
    quote.lte(upperThreshold) && quote.gte(lowerThreshold),
    `Expected ${quote.toString()} to be within [${lowerThreshold.toString()},${upperThreshold.toString()}]. Diff was ${sign}${diffPercentage}%`,
  ).to.be.true;
}

export async function getPriceBetweenTokens(
  networks: { tokenIn: string; tokenOut: string },
  tokenIn: Token,
  tokenOut: Token,
  target: number = 0,
) {
  if (tokenIn.address === tokens.CHAINLINK_USD.address) {
    return 1 / (await fetchPrice(networks.tokenOut, tokenOut.address, target));
  }
  if (tokenOut.address === tokens.CHAINLINK_USD.address) {
    return await fetchPrice(networks.tokenIn, tokenIn.address, target);
  }

  let tokenInPrice = await fetchPrice(
    networks.tokenIn,
    tokenIn.address,
    target,
  );
  let tokenOutPrice = await fetchPrice(
    networks.tokenOut,
    tokenOut.address,
    target,
  );

  return tokenInPrice / tokenOutPrice;
}

let cache: { [address: string]: { [target: number]: number } } = {};

export async function fetchPrice(
  network: string,
  address: string,
  target: number = 0,
): Promise<number> {
  if (!cache[address]) cache[address] = {};
  if (!cache[address][target]) {
    if (target == 0) target = await latest();
    const price = await getPrice(network, address, target);
    cache[address][target] = price;
  }
  return cache[address][target];
}
