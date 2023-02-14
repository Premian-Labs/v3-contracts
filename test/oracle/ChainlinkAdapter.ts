import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ChainlinkAdapter, ChainlinkAdapter__factory } from '../../typechain';

import {
  convertPriceToBigNumberWithDecimals,
  getPrice,
} from '../../utils/defillama';

import { ONE_HOUR, ONE_DAY, now } from '../../utils/time';
import {
  Token,
  CHAINLINK_BTC,
  CHAINLINK_USD,
  CHAINLINK_ETH,
  feeds,
  tokens,
} from '../../utils/addresses';

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
}

let deonominationMapping = [
  { token: tokens.WBTC.address, denomination: CHAINLINK_BTC },
  { token: tokens.WETH.address, denomination: CHAINLINK_ETH },
  { token: tokens.USDC.address, denomination: CHAINLINK_USD },
  { token: tokens.USDT.address, denomination: CHAINLINK_USD },
  { token: tokens.DAI.address, denomination: CHAINLINK_USD },
];

let paths: { path: PricingPath; tokenIn: Token; tokenOut: Token }[][];

// prettier-ignore
{
  paths = [
    [
      // ETH_USD_PAIR
      { path: PricingPath.ETH_USD_PAIR, tokenIn: tokens.WETH, tokenOut: tokens.USDT }, // IN is ETH, OUT is USD
      { path: PricingPath.ETH_USD_PAIR, tokenIn: tokens.USDC, tokenOut: tokens.WETH }, // IN is USD, OUT is ETH
    ],
    [
      // TOKEN_USD_PAIR
      { path: PricingPath.TOKEN_USD_PAIR, tokenIn: tokens.AAVE, tokenOut: tokens.USDT }, // IN (tokenA) => OUT (tokenB) is USD
      { path: PricingPath.TOKEN_USD_PAIR, tokenIn: tokens.CRV, tokenOut: tokens.USDC }, // IN (tokenB) => OUT (tokenA) is USD
      { path: PricingPath.TOKEN_USD_PAIR, tokenIn: tokens.USDC, tokenOut: tokens.COMP }, // IN (tokenA) is USD => OUT (tokenB)
      { path: PricingPath.TOKEN_USD_PAIR, tokenIn: tokens.USDT, tokenOut: tokens.WBTC }, // IN (tokenB) is USD => OUT (tokenA)
    ],
    [
      // TOKEN_ETH_PAIR
      { path: PricingPath.TOKEN_ETH_PAIR, tokenIn: tokens.BNT, tokenOut: tokens.WETH }, // IN (tokenA) => OUT (tokenB) is ETH
      { path: PricingPath.TOKEN_ETH_PAIR, tokenIn: tokens.AXS, tokenOut: tokens.WETH }, // IN (tokenB) => OUT (tokenA) is ETH
      { path: PricingPath.TOKEN_ETH_PAIR, tokenIn: tokens.WETH, tokenOut: tokens.WBTC }, // IN (tokenB) is ETH => OUT (tokenA)
      { path: PricingPath.TOKEN_ETH_PAIR, tokenIn: tokens.WETH, tokenOut: tokens.CRV }, // IN (tokenA) is ETH => OUT (tokenB)
    ],
    [
      // TOKEN_TO_USD_TO_TOKEN_PAIR
      { path: PricingPath.TOKEN_TO_USD_TO_TOKEN_PAIR, tokenIn: tokens.WBTC, tokenOut: tokens.COMP }, // IN (tokenA) => USD => OUT (tokenB)
      { path: PricingPath.TOKEN_TO_USD_TO_TOKEN_PAIR, tokenIn: tokens.CRV, tokenOut: tokens.AAVE }, // IN (tokenB) => USD => OUT (tokenA)
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

      { path: PricingPath.TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B, tokenIn: tokens.FXS, tokenOut: tokens.BOND }, // IN (tokenB) => USD, ETH => OUT (tokenA)
      { path: PricingPath.TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B, tokenIn: tokens.BOND, tokenOut: tokens.FXS }, // IN (tokenA) => ETH, USD => OUT (tokenB)
    ],
  ];
}

describe('ChainlinkAdapter', () => {
  let deployer: SignerWithAddress;
  let notOwner: SignerWithAddress;
  let instance: ChainlinkAdapter;

  before(async () => {
    await ethers.provider.send('hardhat_reset', [
      { forking: { jsonRpcUrl, blockNumber } },
    ]);
  });

  beforeEach(async () => {
    [deployer, notOwner] = await ethers.getSigners();

    instance = await new ChainlinkAdapter__factory(deployer).deploy(
      feeds,
      deonominationMapping,
    );

    await instance.deployed();
  });

  describe('#constructor', () => {
    it('should return max delay (25 hours)', async () => {
      const maxDelay = await instance.maxDelay();
      expect(maxDelay).to.eql(ONE_DAY + ONE_HOUR);
    });

    it('should return tokens mapped to denomination', async () => {
      for (let i = 0; i < deonominationMapping.length; i++) {
        expect(
          await instance.denomination(deonominationMapping[i].token),
        ).to.equal(deonominationMapping[i].denomination);
      }
    });
  });

  describe('#batchRegisterDenominationMappings', () => {
    it('shoud revert if not owner', async () => {
      await expect(
        instance
          .connect(notOwner)
          .batchRegisterDenominationMappings(deonominationMapping),
      ).to.be.revertedWithCustomError(instance, 'Ownable__NotOwner');
    });

    it('shoud return denomination of mapped token', async () => {
      await instance.batchRegisterDenominationMappings(deonominationMapping);

      for (let i = 0; i < deonominationMapping.length; i++) {
        expect(
          await instance.denomination(deonominationMapping[i].token),
        ).to.equal(deonominationMapping[i].denomination);
      }
    });
  });

  describe('#denomination', () => {
    it('shoud return token address if token is not mapped', async () => {
      expect(await instance.denomination(tokens.AMP.address)).to.equal(
        tokens.AMP.address,
      );
    });
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

  describe('#isPairAlreadySupported', () => {
    it('returns false if pair is not supported by adapter', async () => {
      expect(
        await instance.isPairAlreadySupported(
          tokens.WETH.address,
          tokens.DAI.address,
        ),
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
        'Oracle__PairCannotBeSupported',
      );
    });

    it('should not fail if called multiple times for same pair', async () => {
      await instance.addSupportForPairIfNeeded(
        tokens.WETH.address,
        tokens.DAI.address,
      );

      expect(
        await instance.isPairAlreadySupported(
          tokens.WETH.address,
          tokens.DAI.address,
        ),
      ).to.be.true;

      instance.addSupportForPairIfNeeded(
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
      ).to.be.revertedWithCustomError(instance, 'Oracle__TokensAreSame');
    });

    it('should revert if pair has been added', async () => {
      await instance.addSupportForPairIfNeeded(
        tokens.WETH.address,
        tokens.DAI.address,
      );

      expect(
        await instance.isPairAlreadySupported(
          tokens.WETH.address,
          tokens.DAI.address,
        ),
      ).to.be.true;

      await expect(
        instance.addSupportForPairIfNeeded(
          tokens.WETH.address,
          tokens.DAI.address,
        ),
      ).to.be.revertedWithCustomError(instance, 'Oracle__PairAlreadySupported');
    });

    it('should revert if pair does not have a feed', async () => {
      await expect(
        instance.addSupportForPairIfNeeded(
          tokens.EUL.address,
          tokens.DAI.address,
        ),
      ).to.be.revertedWithCustomError(
        instance,
        'Oracle__PairCannotBeSupported',
      );

      await instance.batchRegisterFeedMappings([
        {
          token: tokens.EUL.address,
          denomination: CHAINLINK_USD,
          feed: bnToAddress(BigNumber.from(1)),
        },
      ]);

      await instance.addSupportForPairIfNeeded(
        tokens.EUL.address,
        tokens.DAI.address,
      );
    });

    it('should treat tokenA/tokenB, tokenB/tokenA as separate pairs', async () => {
      await instance.addSupportForPairIfNeeded(
        tokens.WETH.address,
        tokens.DAI.address,
      );

      expect(
        await instance.isPairAlreadySupported(
          tokens.WETH.address,
          tokens.DAI.address,
        ),
      ).to.be.true;

      instance.addSupportForPairIfNeeded(
        tokens.DAI.address,
        tokens.WETH.address,
      );

      expect(
        await instance.isPairAlreadySupported(
          tokens.WETH.address,
          tokens.DAI.address,
        ),
      ).to.be.true;

      expect(
        await instance.isPairAlreadySupported(
          tokens.DAI.address,
          tokens.WETH.address,
        ),
      ).to.be.true;
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
      ).to.be.revertedWithCustomError(instance, 'Oracle__TokensAreSame');
    });

    it('should revert if token or denomination address is 0', async () => {
      await expect(
        instance.batchRegisterFeedMappings([
          {
            token: bnToAddress(BigNumber.from(0)),
            denomination: CHAINLINK_USD,
            feed: bnToAddress(BigNumber.from(1)),
          },
        ]),
      ).to.be.revertedWithCustomError(instance, 'Oracle__ZeroAddress');

      await expect(
        instance.batchRegisterFeedMappings([
          {
            token: tokens.EUL.address,
            denomination: bnToAddress(BigNumber.from(0)),
            feed: bnToAddress(BigNumber.from(1)),
          },
        ]),
      ).to.be.revertedWithCustomError(instance, 'Oracle__ZeroAddress');
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
      expect(await instance.feed(tokens.EUL.address, CHAINLINK_USD)).to.equal(
        bnToAddress(BigNumber.from(0)),
      );
    });
  });

  describe('#quote', async () => {
    it('should revert if pair is not supported yet', async () => {
      await expect(
        instance.quote(tokens.WETH.address, tokens.DAI.address),
      ).to.be.revertedWithCustomError(instance, 'Oracle__PairNotSupportedYet');
    });

    it.skip('should revert if pair not already supported and there is no feed', async () => {});
    it.skip('should add pair if they are not already supported', async () => {});
  });

  describe('supportsInterface', () => {
    it('should return false if interface unknown', async () => {
      expect(await instance.supportsInterface('0x00000000')).to.be.false;
    });

    it('should return false if interface invalid', async () => {
      expect(await instance.supportsInterface('0xffffffff')).to.be.false;
    });

    it('should return true if interface is IERC165', async () => {
      expect(await instance.supportsInterface('0x01ffc9a7')).to.be.true;
    });

    it('should return true if interface is Multicall', async () => {
      expect(await instance.supportsInterface('0xac9650d8')).to.be.true;
    });

    it('should return true if interface is IOracleAdapter', async () => {
      expect(await instance.supportsInterface('0x2b2a0525')).to.be.true;
    });

    it('should return true if interface is IChainlinkAdapter', async () => {
      expect(await instance.supportsInterface('0x74f2cdd5')).to.be.true;
    });
  });

  for (let i = 0; i < paths.length; i++) {
    describe(`${PricingPath[paths[i][0].path]}`, () => {
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

          describe('#isPairAlreadySupported', () => {
            it('should return true if pair is supported by adapter', async () => {
              expect(
                await instance.isPairAlreadySupported(
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
              const quote = await instance.quote(
                tokenIn.address,
                tokenOut.address,
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
