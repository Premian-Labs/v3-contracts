import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {
  StatefulChainlinkOracle,
  StatefulChainlinkOracle__factory,
} from '../../typechain';

import { parseUnits } from 'ethers/lib/utils';

import {
  convertPriceToBigNumberWithDecimals,
  getPrice,
} from '../../utils/defillama';

import { now } from '../../utils/time';
import { Token, tokens } from '../../utils/addresses';

enum PricingPlan {
  NONE,
  ETH_USD_PAIR,
  TOKEN_USD_PAIR,
  TOKEN_ETH_PAIR,
  TOKEN_TO_USD_TO_TOKEN_PAIR,
  TOKEN_TO_ETH_TO_TOKEN_PAIR,
  TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B,
  TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B,
}

let plans: { plan: PricingPlan; tokenIn: Token; tokenOut: Token }[][];

// prettier-ignore
{
  plans = [
    [
      // ETH_USD_PAIR
      { plan: PricingPlan.ETH_USD_PAIR, tokenIn: tokens.WETH, tokenOut: tokens.USDT }, // IN is ETH, OUT is USD
      { plan: PricingPlan.ETH_USD_PAIR, tokenIn: tokens.USDC, tokenOut: tokens.WETH }, // IN is USD, OUT is ETH
    ],
    [
      // TOKEN_USD_PAIR
      { plan: PricingPlan.TOKEN_USD_PAIR, tokenIn: tokens.AAVE, tokenOut: tokens.USDT }, // IN (tokenA) => OUT (tokenB) is USD
      { plan: PricingPlan.TOKEN_USD_PAIR, tokenIn: tokens.CRV, tokenOut: tokens.USDC }, // IN (tokenB) => OUT (tokenA) is USD
      { plan: PricingPlan.TOKEN_USD_PAIR, tokenIn: tokens.USDC, tokenOut: tokens.COMP }, // IN (tokenA) is USD => OUT (tokenB)
      { plan: PricingPlan.TOKEN_USD_PAIR, tokenIn: tokens.USDT, tokenOut: tokens.WBTC }, // IN (tokenB) is USD => OUT (tokenA)
    ],
    [
      // TOKEN_ETH_PAIR
      { plan: PricingPlan.TOKEN_ETH_PAIR, tokenIn: tokens.BNT, tokenOut: tokens.WETH }, // IN (tokenA) => OUT (tokenB) is ETH
      { plan: PricingPlan.TOKEN_ETH_PAIR, tokenIn: tokens.AXS, tokenOut: tokens.WETH }, // IN (tokenB) => OUT (tokenA) is ETH
      { plan: PricingPlan.TOKEN_ETH_PAIR, tokenIn: tokens.WETH, tokenOut: tokens.WBTC }, // IN (tokenB) is ETH => OUT (tokenA)
      { plan: PricingPlan.TOKEN_ETH_PAIR, tokenIn: tokens.WETH, tokenOut: tokens.CRV }, // IN (tokenA) is ETH => OUT (tokenB)
    ],
    [
      // TOKEN_TO_USD_TO_TOKEN_PAIR
      { plan: PricingPlan.TOKEN_TO_USD_TO_TOKEN_PAIR, tokenIn: tokens.WBTC, tokenOut: tokens.COMP }, // IN (tokenA) => USD => OUT (tokenB)
      { plan: PricingPlan.TOKEN_TO_USD_TO_TOKEN_PAIR, tokenIn: tokens.CRV, tokenOut: tokens.AAVE }, // IN (tokenB) => USD => OUT (tokenA)
    ],
    [
      // TOKEN_TO_ETH_TO_TOKEN_PAIR
      { plan: PricingPlan.TOKEN_TO_ETH_TO_TOKEN_PAIR, tokenIn: tokens.BOND, tokenOut: tokens.AXS }, // IN (tokenA) => ETH => OUT (tokenB)
      { plan: PricingPlan.TOKEN_TO_ETH_TO_TOKEN_PAIR, tokenIn: tokens.ALPHA, tokenOut: tokens.BOND }, // IN (tokenB) => ETH => OUT (tokenA)
    ],
    [
      // TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B
      { plan: PricingPlan.TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B, tokenIn: tokens.FXS, tokenOut: tokens.WETH }, // IN (tokenA) => USD, OUT (tokenB) is ETH
      { plan: PricingPlan.TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B, tokenIn: tokens.WETH, tokenOut: tokens.MATIC }, // IN (tokenB) is ETH, USD => OUT (tokenA)

      { plan: PricingPlan.TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B, tokenIn: tokens.USDC, tokenOut: tokens.AXS }, // IN (tokenA) is USD, ETH => OUT (tokenB)
      { plan: PricingPlan.TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B, tokenIn: tokens.ALPHA, tokenOut: tokens.DAI }, // IN (tokenB) => ETH, OUT is USD (tokenA)

      { plan: PricingPlan.TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B, tokenIn: tokens.FXS, tokenOut: tokens.AXS }, // IN (tokenA) => USD, ETH => OUT (tokenB)
      { plan: PricingPlan.TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B, tokenIn: tokens.ALPHA, tokenOut: tokens.MATIC }, // IN (tokenB) => ETH, USD => OUT (tokenA)
    ],
    [
      // TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B
      // We can't test the following two cases, because we would need a token that is
      // supported by chainlink and lower than USD (address(840))
      // - IN (tokenA) => ETH, OUT (tokenB) is USD
      // - IN (tokenB) is USD, ETH => OUT (tokenA)

      { plan: PricingPlan.TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B, tokenIn: tokens.WETH, tokenOut: tokens.AMP }, // IN (tokenA) is ETH, USD => OUT (tokenB)
      { plan: PricingPlan.TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B, tokenIn: tokens.AMP, tokenOut: tokens.WETH }, // IN (tokenB) => USD, OUT is ETH (tokenA)

      { plan: PricingPlan.TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B, tokenIn: tokens.AXS, tokenOut: tokens.AMP }, // IN (tokenA) => ETH, USD => OUT (tokenB)

      { plan: PricingPlan.TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B, tokenIn: tokens.FXS, tokenOut: tokens.BOND }, // IN (tokenB) => USD, ETH => OUT (tokenA)
      { plan: PricingPlan.TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B, tokenIn: tokens.BOND, tokenOut: tokens.FXS }, // IN (tokenA) => ETH, USD => OUT (tokenB)
    ],
  ];
}

// TODO: Set block to 15591000 and chainId to 1, if it is not already set
describe('StatefulChainlinkOracle', () => {
  let deployer: SignerWithAddress;
  let instance: StatefulChainlinkOracle;

  beforeEach(async () => {
    [deployer] = await ethers.getSigners();

    instance = await new StatefulChainlinkOracle__factory(deployer).deploy(
      '0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf',
      deployer.address,
      [deployer.address],
    );

    await instance.deployed();

    await instance
      .connect(deployer)
      .addMappings(
        [
          tokens.WBTC.address,
          tokens.WETH.address,
          tokens.USDC.address,
          tokens.USDT.address,
          tokens.DAI.address,
        ],
        [
          '0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB',
          '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE',
          '0x0000000000000000000000000000000000000348',
          '0x0000000000000000000000000000000000000348',
          '0x0000000000000000000000000000000000000348',
        ],
      );
  });

  describe('#quote', () => {
    for (let i = 0; i < plans.length; i++) {
      describe(`${PricingPlan[plans[i][0].plan]}`, () => {
        for (const { plan, tokenIn, tokenOut } of plans[i]) {
          describe(`${tokenIn.symbol}-${tokenOut.symbol}`, () => {
            beforeEach(async () => {
              await instance.addSupportForPairIfNeeded(
                tokenIn.address,
                tokenOut.address,
                [],
              );
            });

            it(`pricing plan is the correct one`, async () => {
              const plan1 = await instance.planForPair(
                tokenIn.address,
                tokenOut.address,
              );

              const plan2 = await instance.planForPair(
                tokenOut.address,
                tokenIn.address,
              );

              expect(plan1).to.equal(plan);
              expect(plan2).to.equal(plan);
            });

            it(`returns correct quote`, async () => {
              const quote = await instance.quote(
                tokenIn.address,
                parseUnits('1', tokenIn.decimals),
                tokenOut.address,
                [],
              );

              const coingeckoPrice = await getPriceBetweenTokens(
                tokenIn,
                tokenOut,
              );

              const expected = convertPriceToBigNumberWithDecimals(
                coingeckoPrice,
                18,
              );

              validateQuote(quote, expected);
            });
          });
        }
      });
    }
  });
});

const TRESHOLD_PERCENTAGE = 3; // In mainnet, max threshold is usually 2%, but since we are combining pairs, it can sometimes be a little higher

function validateQuote(quote: BigNumber, expected: BigNumber) {
  const threshold = expected.mul(TRESHOLD_PERCENTAGE * 10).div(100 * 10);
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

async function getPriceBetweenTokens(tokenA: Token, tokenB: Token) {
  const tokenAPrice = await fetchPrice(tokenA.address);
  const tokenBPrice = await fetchPrice(tokenB.address);
  return tokenAPrice / tokenBPrice;
}

let priceCache: Map<string, number> = new Map();

async function fetchPrice(address: string): Promise<number> {
  if (!priceCache.has(address)) {
    const timestamp = await now();
    const price = await getPrice('ethereum', address, timestamp);
    priceCache.set(address, price);
  }
  return priceCache.get(address)!;
}
