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

type Token = { address: string; decimals: number; symbol: string };

// TODO: Set block to 15591000 and chainId to 1, if it is not already set

describe('StatefulChainlinkOracle', () => {
  let deployer: SignerWithAddress;
  let instance: StatefulChainlinkOracle;

  const feedRegistry = '0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf';

  const WETH = {
    address: '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2',
    decimals: 18,
    symbol: 'WETH',
  };
  const USDC = {
    address: '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
    decimals: 6,
    symbol: 'USDC',
  };
  const USDT = {
    address: '0xdAC17F958D2ee523a2206206994597C13D831ec7',
    decimals: 6,
    symbol: 'USDT',
  };
  const AAVE = {
    address: '0x7fc66500c84a76ad7e9c93437bfc5ac33e2ddae9',
    decimals: 18,
    symbol: 'AAVE',
  };
  const COMP = {
    address: '0xc00e94cb662c3520282e6f5717214004a7f26888',
    decimals: 18,
    symbol: 'COMP',
  };
  const BNT = {
    address: '0x1f573d6fb3f13d689ff844b4ce37794d79a7ff1c',
    decimals: 18,
    symbol: 'BNT',
  };
  const CRV = {
    address: '0xD533a949740bb3306d119CC777fa900bA034cd52',
    decimals: 18,
    symbol: 'CRV',
  };
  const AMP = {
    address: '0xff20817765cb7f73d4bde2e66e067e58d11095c2',
    decimals: 18,
    symbol: 'AMP',
  };
  const FXS = {
    address: '0x3432b6a60d23ca0dfca7761b7ab56459d9c964d0',
    decimals: 18,
    symbol: 'FXS',
  };
  const ALPHA = {
    address: '0xa1faa113cbe53436df28ff0aee54275c13b40975',
    decimals: 18,
    symbol: 'ALPHA',
  };
  const BOND = {
    address: '0x0391d2021f89dc339f60fff84546ea23e337750f',
    decimals: 18,
    symbol: 'BOND',
  };
  const AXS = {
    address: '0xbb0e17ef65f82ab018d8edd776e8dd940327b28b',
    decimals: 18,
    symbol: 'AXS',
  };
  const MATIC = {
    address: '0x7d1afa7b718fb893db30a3abc0cfc608aacfebb0',
    decimals: 18,
    symbol: 'MATIC',
  };
  const WBTC = {
    address: '0x2260fac5e5542a773aa44fbcfedf7c193bc2c599',
    decimals: 8,
    symbol: 'WBTC',
  };
  const DAI = {
    address: '0x6b175474e89094c44da98b954eedeac495271d0f',
    decimals: 18,
    symbol: 'DAI',
  };

  const PLANS: { tokenIn: Token; tokenOut: Token }[][] = [
    [
      // ETH_USD_PAIR
      { tokenIn: WETH, tokenOut: USDT }, // IN is ETH, OUT is USD
      { tokenIn: USDC, tokenOut: WETH }, // IN is USD, OUT is ETH
    ],
    [
      // TOKEN_USD_PAIR
      { tokenIn: AAVE, tokenOut: USDT }, // IN (tokenA) => OUT (tokenB) is USD
      { tokenIn: CRV, tokenOut: USDC }, // IN (tokenB) => OUT (tokenA) is USD
      { tokenIn: USDC, tokenOut: COMP }, // IN (tokenA) is USD => OUT (tokenB)
      { tokenIn: USDT, tokenOut: WBTC }, // IN (tokenB) is USD => OUT (tokenA)
    ],
    [
      // TOKEN_ETH_PAIR
      { tokenIn: BNT, tokenOut: WETH }, // IN (tokenA) => OUT (tokenB) is ETH
      { tokenIn: AXS, tokenOut: WETH }, // IN (tokenB) => OUT (tokenA) is ETH
      { tokenIn: WETH, tokenOut: WBTC }, // IN (tokenB) is ETH => OUT (tokenA)
      { tokenIn: WETH, tokenOut: CRV }, // IN (tokenA) is ETH => OUT (tokenB)
    ],
    [
      // TOKEN_TO_USD_TO_TOKEN_PAIR
      { tokenIn: WBTC, tokenOut: COMP }, // IN (tokenA) => USD => OUT (tokenB)
      { tokenIn: CRV, tokenOut: AAVE }, // IN (tokenB) => USD => OUT (tokenA)
    ],
    [
      // TOKEN_TO_ETH_TO_TOKEN_PAIR
      { tokenIn: BOND, tokenOut: AXS }, // IN (tokenA) => ETH => OUT (tokenB)
      { tokenIn: ALPHA, tokenOut: BOND }, // IN (tokenB) => ETH => OUT (tokenA)
    ],
    [
      // TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B
      { tokenIn: FXS, tokenOut: WETH }, // IN (tokenA) => USD, OUT (tokenB) is ETH
      { tokenIn: WETH, tokenOut: MATIC }, // IN (tokenB) is ETH, USD => OUT (tokenA)

      { tokenIn: USDC, tokenOut: AXS }, // IN (tokenA) is USD, ETH => OUT (tokenB)
      { tokenIn: ALPHA, tokenOut: DAI }, // IN (tokenB) => ETH, OUT is USD (tokenA)

      { tokenIn: FXS, tokenOut: AXS }, // IN (tokenA) => USD, ETH => OUT (tokenB)
      { tokenIn: ALPHA, tokenOut: MATIC }, // IN (tokenB) => ETH, USD => OUT (tokenA)
    ],
    [
      // TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B
      // We can't test the following two cases, because we would need a token that is
      // supported by chainlink and lower than USD (address(840))
      // - IN (tokenA) => ETH, OUT (tokenB) is USD
      // - IN (tokenB) is USD, ETH => OUT (tokenA)

      { tokenIn: WETH, tokenOut: AMP }, // IN (tokenA) is ETH, USD => OUT (tokenB)
      { tokenIn: AMP, tokenOut: WETH }, // IN (tokenB) => USD, OUT is ETH (tokenA)

      { tokenIn: AXS, tokenOut: AMP }, // IN (tokenA) => ETH, USD => OUT (tokenB)

      { tokenIn: FXS, tokenOut: BOND }, // IN (tokenB) => USD, ETH => OUT (tokenA)
      { tokenIn: BOND, tokenOut: FXS }, // IN (tokenA) => ETH, USD => OUT (tokenB)
    ],
    [
      // SAME_TOKENS
      { tokenIn: USDT, tokenOut: USDC }, // tokenA is USD, tokenB is USD
      { tokenIn: ALPHA, tokenOut: ALPHA }, // tokenA == token B
    ],
  ];

  beforeEach(async () => {
    [deployer] = await ethers.getSigners();

    instance = await new StatefulChainlinkOracle__factory(deployer).deploy(
      feedRegistry,
      deployer.address,
      [deployer.address],
    );

    await instance.deployed();

    await instance
      .connect(deployer)
      .addMappings(
        [WBTC.address, WETH.address, USDC.address, USDT.address, DAI.address],
        [
          '0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB',
          '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE',
          '0x0000000000000000000000000000000000000348',
          '0x0000000000000000000000000000000000000348',
          '0x0000000000000000000000000000000000000348',
        ],
      );
  });

  for (let i = 0; i < PLANS.length; i++) {
    for (const { tokenIn, tokenOut } of PLANS[i]) {
      describe(`quote (${tokenIn.symbol}, ${tokenOut.symbol})`, () => {
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

          expect(plan1).to.equal(i + 1);
          expect(plan2).to.equal(i + 1);
        });

        it(`returns correct quote`, async () => {
          const quote = await instance.quote(
            tokenIn.address,
            parseUnits('1', tokenIn.decimals),
            tokenOut.address,
            [],
          );

          const coingeckoPrice = await getPriceBetweenTokens(tokenIn, tokenOut);

          const expected = convertPriceToBigNumberWithDecimals(
            coingeckoPrice,
            18,
          );

          validateQuote(quote, expected);
        });
      });
    }
  }
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

// describe.skip('', () => {
//   it('', async () => {
//     await instance.addMappings(
//       [WETH.address],
//       ['0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE'],
//     );

//     // console.log(await instance.canSupportPair(WETH.address, USDC.address));
//     // console.log(await instance.canSupportPair(USDC.address, WETH.address));
//     // console.log(await instance.canSupportPair(AAVE.address, USDC.address));
//     // console.log(await instance.canSupportPair(AAVE.address, WETH.address));

//     await instance.addOrModifySupportForPair(
//       WETH.address,
//       USDC.address,
//       '0x',
//     );
//     await instance.addOrModifySupportForPair(
//       USDC.address,
//       WETH.address,
//       '0x',
//     );
//     await instance.addOrModifySupportForPair(
//       AAVE.address,
//       USDC.address,
//       '0x',
//     );
//     await instance.addOrModifySupportForPair(
//       AAVE.address,
//       WETH.address,
//       '0x',
//     );
//     await instance.addOrModifySupportForPair(
//       WETH.address,
//       AAVE.address,
//       '0x',
//     );
//     await instance.addOrModifySupportForPair(FXS.address, WETH.address, '0x');
//     await instance.addOrModifySupportForPair(WETH.address, FXS.address, '0x');

//     // console.log(await instance.planForPair(WETH.address, USDC.address));
//     // console.log(await instance.planForPair(USDC.address, WETH.address));
//     // console.log(await instance.planForPair(AAVE.address, USDC.address));
//     // console.log(await instance.planForPair(AAVE.address, WETH.address));
//     // console.log(await instance.planForPair(FXS.address, WETH.address));
//     // console.log(await instance.planForPair(WETH.address, FXS.address));

//     console.log(
//       'WETH/USDC',
//       await instance.quote(WETH.address, parseEther('1'), USDC.address, '0x'),
//     );

//     console.log(
//       'USDC/WETH',
//       await instance.quote(USDC.address, parseEther('1'), WETH.address, '0x'),
//     );

//     console.log(
//       'AAVE/USDC',
//       await instance.quote(AAVE.address, parseEther('1'), USDC.address, '0x'),
//     );

//     console.log(
//       'USDC/AAVE',
//       await instance.quote(USDC.address, parseEther('1'), AAVE.address, '0x'),
//     );

//     console.log(
//       'AAVE/WETH',
//       await instance.quote(AAVE.address, parseEther('1'), WETH.address, '0x'),
//     );

//     console.log(
//       'WETH/AAVE',
//       await instance.quote(WETH.address, parseEther('1'), AAVE.address, '0x'),
//     );

//     console.log(
//       'FXS/WETH',
//       await instance.quote(FXS.address, parseEther('1'), WETH.address, '0x'),
//     );

//     console.log(
//       'WETH/FXS',
//       await instance.quote(WETH.address, parseEther('1'), FXS.address, '0x'),
//     );
//   });
// });
