import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {
  ChainlinkAdapter,
  ChainlinkAdapter__factory,
  ChainlinkAdapterProxy__factory,
} from '../../typechain';

import {
  convertPriceToBigNumberWithDecimals,
  getPrice,
} from '../../utils/defillama';

import { ONE_ETHER } from '../../utils/constants';
import { now } from '../../utils/time';
import { Token, feeds, tokens } from '../../utils/addresses';

import { bnToAddress } from '@solidstate/library';

const { API_KEY_ALCHEMY } = process.env;
const jsonRpcUrl = `https://eth-mainnet.alchemyapi.io/v2/${API_KEY_ALCHEMY}`;
const blockNumber = 16600000;

enum PricingPath {
  NONE,
  ETH_USD_PAIR,
  TOKEN_USD_PAIR,
  TOKEN_ETH_PAIR,
  TOKEN_TO_USD_TO_TOKEN_PAIR,
  TOKEN_TO_ETH_TO_TOKEN_PAIR,
  TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B,
  TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B,
  TOKEN_A_TO_BTC_TO_USD_TO_TOKEN_B,
}

let paths: { path: PricingPath; tokenIn: Token; tokenOut: Token }[][];

// prettier-ignore
{
  paths = [
    [
      // ETH_USD_PAIR
      { path: PricingPath.ETH_USD_PAIR, tokenIn: tokens.WETH, tokenOut: tokens.CHAINLINK_USD }, // IN is ETH, OUT is USD
      { path: PricingPath.ETH_USD_PAIR, tokenIn: tokens.CHAINLINK_USD, tokenOut: tokens.WETH }, // IN is USD, OUT is ETH
      { path: PricingPath.ETH_USD_PAIR, tokenIn: tokens.CHAINLINK_ETH, tokenOut: tokens.CHAINLINK_USD }, // IN is ETH, OUT is USD
    ],
    [
      // TOKEN_USD_PAIR
      { path: PricingPath.TOKEN_USD_PAIR, tokenIn: tokens.DAI, tokenOut: tokens.CHAINLINK_USD }, // IN (tokenA) => OUT (tokenB) is USD
      { path: PricingPath.TOKEN_USD_PAIR, tokenIn: tokens.AAVE, tokenOut: tokens.CHAINLINK_USD }, // IN (tokenA) => OUT (tokenB) is USD
    ],
    [
      // TOKEN_ETH_PAIR
      { path: PricingPath.TOKEN_ETH_PAIR, tokenIn: tokens.BNT, tokenOut: tokens.WETH }, // IN (tokenA) => OUT (tokenB) is ETH
      { path: PricingPath.TOKEN_ETH_PAIR, tokenIn: tokens.AXS, tokenOut: tokens.WETH }, // IN (tokenB) => OUT (tokenA) is ETH
      { path: PricingPath.TOKEN_ETH_PAIR, tokenIn: tokens.WETH, tokenOut: tokens.CRV }, // IN (tokenA) is ETH => OUT (tokenB)
    ],
    [
      // TOKEN_TO_USD_TO_TOKEN_PAIR
      { path: PricingPath.TOKEN_TO_USD_TO_TOKEN_PAIR, tokenIn: tokens.CRV, tokenOut: tokens.AAVE }, // IN (tokenB) => USD => OUT (tokenA)
      { path: PricingPath.TOKEN_TO_USD_TO_TOKEN_PAIR, tokenIn: tokens.DAI, tokenOut: tokens.AAVE }, // IN (tokenA) => USD => OUT (tokenB)
      { path: PricingPath.TOKEN_TO_USD_TO_TOKEN_PAIR, tokenIn: tokens.AAVE, tokenOut: tokens.DAI }, // IN (tokenB) => USD => OUT (tokenA)

      { path: PricingPath.TOKEN_TO_USD_TO_TOKEN_PAIR, tokenIn: tokens.CRV, tokenOut: tokens.USDC }, // IN (tokenB) => USD => OUT (tokenA)
      { path: PricingPath.TOKEN_TO_USD_TO_TOKEN_PAIR, tokenIn: tokens.USDC, tokenOut: tokens.COMP }, // IN (tokenA) => USD => OUT (tokenB)
    ],
    [
      // TOKEN_TO_ETH_TO_TOKEN_PAIR
      { path: PricingPath.TOKEN_TO_ETH_TO_TOKEN_PAIR, tokenIn: tokens.BOND, tokenOut: tokens.AXS }, // IN (tokenA) => ETH => OUT (tokenB)
      { path: PricingPath.TOKEN_TO_ETH_TO_TOKEN_PAIR, tokenIn: tokens.ALPHA, tokenOut: tokens.BOND }, // IN (tokenB) => ETH => OUT (tokenA)
    ],
    [
      // TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B
      { path: PricingPath.TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B, tokenIn: tokens.FXS, tokenOut: tokens.WETH }, // IN (tokenA) => USD, OUT (tokenB) is ETH
      { path: PricingPath.TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B, tokenIn: tokens.WETH, tokenOut: tokens.MATIC }, // IN (tokenB) is ETH, USD => OUT (tokenA)

      { path: PricingPath.TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B, tokenIn: tokens.USDC, tokenOut: tokens.AXS }, // IN (tokenA) is USD, ETH => OUT (tokenB)
      { path: PricingPath.TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B, tokenIn: tokens.ALPHA, tokenOut: tokens.DAI }, // IN (tokenB) => ETH, OUT is USD (tokenA)
      { path: PricingPath.TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B, tokenIn: tokens.DAI, tokenOut: tokens.ALPHA }, 

      { path: PricingPath.TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B, tokenIn: tokens.FXS, tokenOut: tokens.AXS }, // IN (tokenA) => USD, ETH => OUT (tokenB)
      { path: PricingPath.TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B, tokenIn: tokens.ALPHA, tokenOut: tokens.MATIC }, // IN (tokenB) => ETH, USD => OUT (tokenA)
    ],
    [
      // TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B
      // We can't test the following two cases, because we would need a token that is
      // supported by chainlink and lower than USD (address(840))
      // - IN (tokenA) => ETH, OUT (tokenB) is USD
      // - IN (tokenB) is USD, ETH => OUT (tokenA)

      { path: PricingPath.TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B, tokenIn: tokens.WETH, tokenOut: tokens.IMX }, // IN (tokenA) is ETH, USD => OUT (tokenB)
      { path: PricingPath.TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B, tokenIn: tokens.IMX, tokenOut: tokens.WETH }, // IN (tokenB) => USD, OUT is ETH (tokenA)

      { path: PricingPath.TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B, tokenIn: tokens.AXS, tokenOut: tokens.IMX }, // IN (tokenA) => ETH, USD => OUT (tokenB)

      { path: PricingPath.TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B, tokenIn: tokens.FXS, tokenOut: tokens.BOND }, // IN (tokenB) => ETH, USD => OUT (tokenA)
      { path: PricingPath.TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B, tokenIn: tokens.BOND, tokenOut: tokens.FXS }, // IN (tokenA) => USD, ETH => OUT (tokenB) 
    ],
    [
      // TOKEN_A_TO_BTC_TO_USD_TO_TOKEN_B
      { path: PricingPath.TOKEN_A_TO_BTC_TO_USD_TO_TOKEN_B, tokenIn: tokens.WBTC, tokenOut: tokens.WETH }, // IN (tokenA) => BTC, OUT is ETH (tokenB)
      { path: PricingPath.TOKEN_A_TO_BTC_TO_USD_TO_TOKEN_B, tokenIn: tokens.WETH, tokenOut: tokens.WBTC }, // IN (tokenB) is ETH, BTC => OUT (tokenA)
      { path: PricingPath.TOKEN_A_TO_BTC_TO_USD_TO_TOKEN_B, tokenIn: tokens.DAI, tokenOut: tokens.WBTC }, // IN (tokenB) => USD, BTC => OUT (tokenA)
      { path: PricingPath.TOKEN_A_TO_BTC_TO_USD_TO_TOKEN_B, tokenIn: tokens.WBTC, tokenOut: tokens.USDC }, // IN (tokenA) => BTC, USD => OUT (tokenB)
      { path: PricingPath.TOKEN_A_TO_BTC_TO_USD_TO_TOKEN_B, tokenIn: tokens.WBTC, tokenOut: tokens.BNT }, // IN (tokenA) => USD,  BTC => OUT (tokenB)
    ]
  ];
}

describe('ChainlinkAdapter', () => {
  let deployer: SignerWithAddress;
  let instance: ChainlinkAdapter;

  before(async () => {
    await ethers.provider.send('hardhat_reset', [
      { forking: { jsonRpcUrl, blockNumber } },
    ]);
  });

  beforeEach(async () => {
    [deployer] = await ethers.getSigners();

    const implementation = await new ChainlinkAdapter__factory(
      deployer,
    ).deploy();

    await implementation.deployed();

    const proxy = await new ChainlinkAdapterProxy__factory(deployer).deploy(
      implementation.address,
      tokens.WETH.address,
      feeds,
    );

    await proxy.deployed();

    instance = ChainlinkAdapter__factory.connect(proxy.address, deployer);
  });

  describe('#canSupportPair', () => {
    it('returns false if adapter cannot support pair', async () => {
      expect(
        await instance.canSupportPair(
          bnToAddress(BigNumber.from(0)),
          tokens.WETH.address,
        ),
      ).to.be.false;
    });
  });

  describe('#isPairSupported', () => {
    it('returns false if pair is not supported by adapter', async () => {
      expect(
        await instance.isPairSupported(tokens.WETH.address, tokens.DAI.address),
      ).to.be.false;
    });
  });

  describe('#addOrModifySupportForPair', () => {
    it('should revert if pair cannot be supported', async () => {
      await expect(
        instance.addOrModifySupportForPair(
          bnToAddress(BigNumber.from(0)),
          tokens.WETH.address,
        ),
      ).to.be.revertedWithCustomError(
        instance,
        'OracleAdapter__PairCannotBeSupported',
      );
    });

    it('should not fail if called multiple times for same pair', async () => {
      await instance.addOrModifySupportForPair(
        tokens.WETH.address,
        tokens.DAI.address,
      );

      expect(
        await instance.isPairSupported(tokens.WETH.address, tokens.DAI.address),
      ).to.be.true;

      await instance.addOrModifySupportForPair(
        tokens.WETH.address,
        tokens.DAI.address,
      );
    });
  });

  describe('#addSupportForPairIfNeeded', () => {
    it('should revert if pair contains like assets', async () => {
      await expect(
        instance.addSupportForPairIfNeeded(
          tokens.WETH.address,
          tokens.WETH.address,
        ),
      ).to.be.revertedWithCustomError(instance, 'OracleAdapter__TokensAreSame');
    });

    it('should revert if pair has been added', async () => {
      await instance.addSupportForPairIfNeeded(
        tokens.WETH.address,
        tokens.DAI.address,
      );

      expect(
        await instance.isPairSupported(tokens.WETH.address, tokens.DAI.address),
      ).to.be.true;

      await expect(
        instance.addSupportForPairIfNeeded(
          tokens.WETH.address,
          tokens.DAI.address,
        ),
      ).to.be.revertedWithCustomError(
        instance,
        'OracleAdapter__PairAlreadySupported',
      );
    });

    it('should revert if pair does not have a feed', async () => {
      await expect(
        instance.addSupportForPairIfNeeded(
          tokens.EUL.address,
          tokens.DAI.address,
        ),
      ).to.be.revertedWithCustomError(
        instance,
        'OracleAdapter__PairCannotBeSupported',
      );

      await instance.batchRegisterFeedMappings([
        {
          token: tokens.EUL.address,
          denomination: tokens.CHAINLINK_USD.address,
          feed: bnToAddress(BigNumber.from(1)),
        },
      ]);

      await instance.addSupportForPairIfNeeded(
        tokens.EUL.address,
        tokens.DAI.address,
      );
    });
  });

  describe('#bathRegisterFeedMappings', async () => {
    it('should revert if token == denomination', async () => {
      await expect(
        instance.batchRegisterFeedMappings([
          {
            token: tokens.EUL.address,
            denomination: tokens.EUL.address,
            feed: bnToAddress(BigNumber.from(1)),
          },
        ]),
      ).to.be.revertedWithCustomError(instance, 'OracleAdapter__TokensAreSame');
    });

    it('should revert if token or denomination address is 0', async () => {
      await expect(
        instance.batchRegisterFeedMappings([
          {
            token: bnToAddress(BigNumber.from(0)),
            denomination: tokens.DAI.address,
            feed: bnToAddress(BigNumber.from(1)),
          },
        ]),
      ).to.be.revertedWithCustomError(instance, 'OracleAdapter__ZeroAddress');

      await expect(
        instance.batchRegisterFeedMappings([
          {
            token: tokens.EUL.address,
            denomination: bnToAddress(BigNumber.from(0)),
            feed: bnToAddress(BigNumber.from(1)),
          },
        ]),
      ).to.be.revertedWithCustomError(instance, 'OracleAdapter__ZeroAddress');
    });

    it('shoud return feed of mapped token and denomination', async () => {
      await instance.batchRegisterFeedMappings(feeds);

      for (let i = 0; i < feeds.length; i++) {
        expect(
          await instance.feed(feeds[i].token, feeds[i].denomination),
        ).to.equal(feeds[i].feed);
      }
    });
  });

  describe('#feed', async () => {
    it('should return zero address if feed has not been added', async () => {
      expect(
        await instance.feed(tokens.EUL.address, tokens.DAI.address),
      ).to.equal(bnToAddress(BigNumber.from(0)));
    });
  });

  describe('#tryQuote', async () => {
    it('should revert if pair not already supported and there is no feed', async () => {
      await expect(
        instance.tryQuote(tokens.EUL.address, tokens.DAI.address),
      ).to.be.revertedWithCustomError(
        instance,
        'OracleAdapter__PairCannotBeSupported',
      );
    });

    it('should add pair if they are not already supported', async () => {
      const tokenIn = tokens.WETH;
      const tokenOut = tokens.DAI;

      expect(await instance.isPairSupported(tokenIn.address, tokenOut.address))
        .to.be.false;

      await instance.tryQuote(tokenIn.address, tokenOut.address);

      expect(await instance.isPairSupported(tokenIn.address, tokenOut.address))
        .to.be.true;
    });

    it('should return quote for pair', async () => {
      const tokenIn = tokens.WETH;
      const tokenOut = tokens.DAI;

      const quote = await instance.callStatic['tryQuote(address,address)'](
        tokenIn.address,
        tokenOut.address,
      );

      const coingeckoPrice = await getPriceBetweenTokens(tokenIn, tokenOut);
      const expected = convertPriceToBigNumberWithDecimals(coingeckoPrice, 18);

      validateQuote(quote, expected);
    });
  });

  describe('#quote', async () => {
    it('should revert if pair is not supported yet', async () => {
      await expect(
        instance.quote(tokens.WETH.address, tokens.DAI.address),
      ).to.be.revertedWithCustomError(
        instance,
        'OracleAdapter__PairNotSupported',
      );
    });

    it('should return quote using correct denomination', async () => {
      let tokenIn = tokens.WETH;
      let tokenOut = tokens.DAI;

      await instance.addSupportForPairIfNeeded(
        tokenIn.address,
        tokenOut.address,
      );

      let quote = await instance.quote(tokenIn.address, tokenOut.address);
      let invertedQuote = await instance.quote(
        tokenOut.address,
        tokenIn.address,
      );

      expect(quote.div(ONE_ETHER)).to.be.eq(ONE_ETHER.div(invertedQuote));

      tokenIn = tokens.CRV;
      tokenOut = tokens.AAVE;

      await instance.addSupportForPairIfNeeded(
        tokenIn.address,
        tokenOut.address,
      );

      quote = await instance.quote(tokenIn.address, tokenOut.address);
      invertedQuote = await instance.quote(tokenOut.address, tokenIn.address);

      expect(quote.div(ONE_ETHER)).to.be.eq(ONE_ETHER.div(invertedQuote));
    });
  });

  for (let i = 0; i < paths.length; i++) {
    describe.only(`${PricingPath[paths[i][0].path]}`, () => {
      for (const { path, tokenIn, tokenOut } of paths[i]) {
        describe(`${tokenIn.symbol}-${tokenOut.symbol}`, () => {
          beforeEach(async () => {
            await instance.addSupportForPairIfNeeded(
              tokenIn.address,
              tokenOut.address,
            );
          });

          describe('#canSupportPair', () => {
            it('should return true if adapter can support pair', async () => {
              expect(
                await instance.canSupportPair(
                  tokenIn.address,
                  tokenOut.address,
                ),
              ).to.be.true;
            });
          });

          describe('#isPairSupported', () => {
            it('should return true if pair is supported by adapter', async () => {
              expect(
                await instance.isPairSupported(
                  tokenIn.address,
                  tokenOut.address,
                ),
              ).to.be.true;
            });
          });

          describe('#pathForPair', () => {
            it('should return pricing path for pair', async () => {
              const path1 = await instance.pathForPair(
                tokenIn.address,
                tokenOut.address,
              );

              const path2 = await instance.pathForPair(
                tokenOut.address,
                tokenIn.address,
              );

              expect(path1).to.equal(path);
              expect(path2).to.equal(path);
            });
          });

          describe('#quote', async () => {
            it('should return quote for pair', async () => {
              let _tokenIn = Object.assign({}, tokenIn);
              let _tokenOut = Object.assign({}, tokenOut);

              const quote = await instance.quote(
                _tokenIn.address,
                _tokenOut.address,
              );

              if (tokenIn.symbol === tokens.CHAINLINK_ETH.symbol) {
                _tokenIn.address = tokens.WETH.address;
              }

              if (tokenOut.symbol === tokens.CHAINLINK_ETH.symbol) {
                _tokenOut.address = tokens.WETH.address;
              }

              if (tokenIn.symbol === tokens.CHAINLINK_USD.symbol) {
                _tokenIn.address = tokens.DAI.address;
              }

              if (tokenOut.symbol === tokens.CHAINLINK_USD.symbol) {
                _tokenOut.address = tokens.DAI.address;
              }

              const coingeckoPrice = await getPriceBetweenTokens(
                _tokenIn,
                _tokenOut,
              );

              const expected = convertPriceToBigNumberWithDecimals(
                coingeckoPrice,
                18,
              );

              validateQuote(quote, expected);
            });
          });
        });
      }
    });
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
