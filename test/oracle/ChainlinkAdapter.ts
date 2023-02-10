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
  tokens,
} from '../../utils/addresses';

const { API_KEY_ALCHEMY } = process.env;
const jsonRpcUrl = `https://eth-mainnet.alchemyapi.io/v2/${API_KEY_ALCHEMY}`;
const blockNumber = 15591000;

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

const feedRegistryAddress = '0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf';

let tokenAddressMapping = [
  tokens.WBTC.address,
  tokens.WETH.address,
  tokens.USDC.address,
  tokens.USDT.address,
  tokens.DAI.address,
];

let chainlinkAddressMapping = [
  CHAINLINK_BTC,
  CHAINLINK_ETH,
  CHAINLINK_USD,
  CHAINLINK_USD,
  CHAINLINK_USD,
];

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
      feedRegistryAddress,
      tokenAddressMapping,
      chainlinkAddressMapping,
    );

    await instance.deployed();
  });

  describe('#constructor', () => {
    describe('should revert if', () => {
      it('feed registry is zero address', async () => {
        await expect(
          new ChainlinkAdapter__factory(deployer).deploy(
            ethers.constants.AddressZero,
            tokenAddressMapping,
            chainlinkAddressMapping,
          ),
        ).to.be.revertedWithCustomError(instance, 'Oracle__ZeroAddress');
      });

      describe('on successful deployment', () => {
        it('registry is set correctly', async () => {
          const registry = await instance.feedRegistry();
          expect(registry).to.eql(feedRegistryAddress);
        });

        it('max delay is set correctly', async () => {
          const maxDelay = await instance.maxDelay();
          expect(maxDelay).to.eql(ONE_DAY + ONE_HOUR);
        });

        it('tokens are mapped correctly', async () => {
          for (let i = 0; i < tokenAddressMapping.length; i++) {
            expect(await instance.mappedToken(tokenAddressMapping[i])).to.equal(
              chainlinkAddressMapping[i],
            );
          }
        });
      });
    });
  });

  describe('#addMappings', () => {
    const tokenAddressMapping = [
      tokens.CRV.address,
      tokens.AAVE.address,
      tokens.MATIC.address,
    ];

    const chainlinkAddressMapping = [
      '0x0000000000000000000000000000000000000001',
      '0x0000000000000000000000000000000000000002',
      '0x0000000000000000000000000000000000000003',
    ];

    it('shoud revert if not owner', async () => {
      await expect(
        instance
          .connect(notOwner)
          .addMappings(tokenAddressMapping, chainlinkAddressMapping),
      ).to.be.revertedWithCustomError(instance, 'Ownable__NotOwner');
    });

    it('shoud return token address if token is not mapped', async () => {
      await instance.addMappings(tokenAddressMapping, chainlinkAddressMapping);

      for (let i = 0; i < tokenAddressMapping.length; i++) {
        expect(await instance.mappedToken(tokenAddressMapping[i])).to.equal(
          chainlinkAddressMapping[i],
        );
      }
    });
  });

  describe('#mappedToken', () => {
    it('shoud return token address if token is not mapped', async () => {
      expect(await instance.mappedToken(tokens.AMP.address)).to.equal(
        tokens.AMP.address,
      );
    });
  });

  describe('#canSupportPair', () => {
    it('returns false if adapter cannot support pair', async () => {
      expect(
        await instance.canSupportPair(
          ethers.constants.AddressZero,
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
          ethers.constants.AddressZero,
          tokens.WETH.address,
          [],
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
        [],
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
        [],
      );
    });
  });

  describe('#addSupportForPairIfNeeded', () => {
    it('should revert if pair contains like assets', async () => {
      await expect(
        instance.addSupportForPairIfNeeded(
          tokens.WETH.address,
          tokens.WETH.address,
          [],
        ),
      ).to.be.revertedWithCustomError(instance, 'Oracle__BaseAndQuoteAreSame');
    });

    it('should revert if pair has been added', async () => {
      await instance.addSupportForPairIfNeeded(
        tokens.WETH.address,
        tokens.DAI.address,
        [],
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
          [],
        ),
      ).to.be.revertedWithCustomError(instance, 'Oracle__PairAlreadySupported');
    });

    it('should treat tokenA/tokenB, tokenB/tokenA as separate pairs', async () => {
      await instance.addSupportForPairIfNeeded(
        tokens.WETH.address,
        tokens.DAI.address,
        [],
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
        [],
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

  describe('#quote', async () => {
    it('should revert if pair is not supported yet', async () => {
      await expect(
        instance.quote(tokens.WETH.address, tokens.DAI.address, []),
      ).to.be.revertedWithCustomError(instance, 'Oracle__PairNotSupportedYet');
    });
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
      expect(await instance.supportsInterface('0x07252f69')).to.be.true;
    });

    it('should return true if interface is IChainlinkAdapter', async () => {
      expect(await instance.supportsInterface('0xc5f65fd0')).to.be.true;
    });
  });

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

          describe('#canSupportPair', () => {
            it('returns true if adapter can support pair', async () => {
              expect(
                await instance.canSupportPair(
                  tokenIn.address,
                  tokenOut.address,
                ),
              ).to.be.true;
            });
          });

          describe('#isPairAlreadySupported', () => {
            it('returns true if pair is supported by adapter', async () => {
              expect(
                await instance.isPairAlreadySupported(
                  tokenIn.address,
                  tokenOut.address,
                ),
              ).to.be.true;
            });
          });

          describe('#planForPair', () => {
            it('returns pricing plan for pair', async () => {
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
          });

          describe('#quote', async () => {
            it('returns quote for pair', async () => {
              const quote = await instance.quote(
                tokenIn.address,
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
