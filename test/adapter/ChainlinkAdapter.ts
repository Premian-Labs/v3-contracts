import {
  ChainlinkAdapter,
  ChainlinkAdapter__factory,
  ProxyUpgradeableOwnable__factory,
  ChainlinkOraclePriceStub__factory,
} from '../../typechain';
import { feeds, Token, tokens } from '../../utils/addresses';
import { ONE_ETHER } from '../../utils/constants';
import {
  convertPriceToBigNumberWithDecimals,
  getPriceBetweenTokens,
  validateQuote,
} from '../../utils/defillama';
import { AdapterType } from '../../utils/sdk/types';
import { increaseTo, latest } from '../../utils/time';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { bnToAddress } from '@solidstate/library';
import { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';

const target = 1676016000; // Fri Feb 10 2023 08:00:00 GMT+0000

enum PricingPath {
  NONE,
  ETH_USD,
  TOKEN_USD,
  TOKEN_ETH,
  TOKEN_USD_TOKEN,
  TOKEN_ETH_TOKEN,
  A_USD_ETH_B,
  A_ETH_USD_B,
  TOKEN_USD_BTC_WBTC,
}

enum FailureMode {
  NONE,
  GET_ROUND_DATA_REVERT_WITH_REASON,
  GET_ROUND_DATA_REVERT,
  LAST_ROUND_DATA_REVERT_WITH_REASON,
  LAST_ROUND_DATA_REVERT,
}

let paths: { path: PricingPath; tokenIn: Token; tokenOut: Token }[][];

// prettier-ignore
{
  paths = [
    [
      // ETH_USD
      { path: PricingPath.ETH_USD, tokenIn: tokens.WETH, tokenOut: tokens.CHAINLINK_USD }, // IN is ETH, OUT is USD
      { path: PricingPath.ETH_USD, tokenIn: tokens.CHAINLINK_USD, tokenOut: tokens.WETH }, // IN is USD, OUT is ETH
      { path: PricingPath.ETH_USD, tokenIn: tokens.CHAINLINK_ETH, tokenOut: tokens.CHAINLINK_USD }, // IN is ETH, OUT is USD
    ],
    [
      // TOKEN_USD
      { path: PricingPath.TOKEN_USD, tokenIn: tokens.DAI, tokenOut: tokens.CHAINLINK_USD }, // IN (tokenA) => OUT (tokenB) is USD
      { path: PricingPath.TOKEN_USD, tokenIn: tokens.AAVE, tokenOut: tokens.CHAINLINK_USD }, // IN (tokenA) => OUT (tokenB) is USD

      // Note: Assumes WBTC/USD feed exists
      { path: PricingPath.TOKEN_USD, tokenIn: tokens.CHAINLINK_USD, tokenOut: tokens.WBTC }, // IN (tokenB) is USD => OUT (tokenA)
      { path: PricingPath.TOKEN_USD, tokenIn: tokens.WBTC, tokenOut: tokens.CHAINLINK_USD }, // IN (tokenA) => OUT (tokenB) is USD
    ],
    [
      // TOKEN_ETH
      { path: PricingPath.TOKEN_ETH, tokenIn: tokens.BNT, tokenOut: tokens.WETH }, // IN (tokenA) => OUT (tokenB) is ETH
      { path: PricingPath.TOKEN_ETH, tokenIn: tokens.AXS, tokenOut: tokens.WETH }, // IN (tokenB) => OUT (tokenA) is ETH
      { path: PricingPath.TOKEN_ETH, tokenIn: tokens.WETH, tokenOut: tokens.CRV }, // IN (tokenA) is ETH => OUT (tokenB)
    ],
    [
      // TOKEN_USD_TOKEN
      { path: PricingPath.TOKEN_USD_TOKEN, tokenIn: tokens.CRV, tokenOut: tokens.AAVE }, // IN (tokenB) => USD => OUT (tokenA)
      { path: PricingPath.TOKEN_USD_TOKEN, tokenIn: tokens.DAI, tokenOut: tokens.AAVE }, // IN (tokenA) => USD => OUT (tokenB)
      { path: PricingPath.TOKEN_USD_TOKEN, tokenIn: tokens.AAVE, tokenOut: tokens.DAI }, // IN (tokenB) => USD => OUT (tokenA)
      { path: PricingPath.TOKEN_USD_TOKEN, tokenIn: tokens.CRV, tokenOut: tokens.USDC }, // IN (tokenB) => USD => OUT (tokenA)
      { path: PricingPath.TOKEN_USD_TOKEN, tokenIn: tokens.USDC, tokenOut: tokens.COMP }, // IN (tokenA) => USD => OUT (tokenB)

      // Note: Assumes WBTC/USD feed exists
      { path: PricingPath.TOKEN_USD_TOKEN, tokenIn: tokens.DAI, tokenOut: tokens.WBTC }, // IN (tokenB) => USD => OUT (tokenA)
      { path: PricingPath.TOKEN_USD_TOKEN, tokenIn: tokens.WBTC, tokenOut: tokens.USDC }, // IN (tokenA) => USD => OUT (tokenB)
    ],
    [
      // TOKEN_ETH_TOKEN
      { path: PricingPath.TOKEN_ETH_TOKEN, tokenIn: tokens.BOND, tokenOut: tokens.AXS }, // IN (tokenA) => ETH => OUT (tokenB)
      { path: PricingPath.TOKEN_ETH_TOKEN, tokenIn: tokens.ALPHA, tokenOut: tokens.BOND }, // IN (tokenB) => ETH => OUT (tokenA)
    ],
    [
      // A_USD_ETH_B
      { path: PricingPath.A_USD_ETH_B, tokenIn: tokens.FXS, tokenOut: tokens.WETH }, // IN (tokenA) => USD, OUT (tokenB) is ETH
      { path: PricingPath.A_USD_ETH_B, tokenIn: tokens.WETH, tokenOut: tokens.MATIC }, // IN (tokenB) is ETH, USD => OUT (tokenA)

      { path: PricingPath.A_USD_ETH_B, tokenIn: tokens.USDC, tokenOut: tokens.AXS }, // IN (tokenA) is USD, ETH => OUT (tokenB)
      { path: PricingPath.A_USD_ETH_B, tokenIn: tokens.ALPHA, tokenOut: tokens.DAI }, // IN (tokenB) => ETH, OUT is USD (tokenA)
      { path: PricingPath.A_USD_ETH_B, tokenIn: tokens.DAI, tokenOut: tokens.ALPHA }, 

      { path: PricingPath.A_USD_ETH_B, tokenIn: tokens.FXS, tokenOut: tokens.AXS }, // IN (tokenA) => USD, ETH => OUT (tokenB)
      { path: PricingPath.A_USD_ETH_B, tokenIn: tokens.ALPHA, tokenOut: tokens.MATIC }, // IN (tokenB) => ETH, USD => OUT (tokenA)

      // Note: Assumes WBTC/USD feed exists
      { path: PricingPath.A_USD_ETH_B, tokenIn: tokens.WETH, tokenOut: tokens.WBTC }, // IN (tokenB) => ETH, USD => OUT (tokenA)
    ],
    [
      // A_ETH_USD_B
      // We can't test the following two cases, because we would need a token that is
      // supported by chainlink and lower than USD (address(840))
      // - IN (tokenA) => ETH, OUT (tokenB) is USD
      // - IN (tokenB) is USD, ETH => OUT (tokenA)

      { path: PricingPath.A_ETH_USD_B, tokenIn: tokens.WETH, tokenOut: tokens.IMX }, // IN (tokenA) is ETH, USD => OUT (tokenB)
      { path: PricingPath.A_ETH_USD_B, tokenIn: tokens.IMX, tokenOut: tokens.WETH }, // IN (tokenB) => USD, OUT is ETH (tokenA)

      { path: PricingPath.A_ETH_USD_B, tokenIn: tokens.AXS, tokenOut: tokens.IMX }, // IN (tokenA) => ETH, USD => OUT (tokenB)

      { path: PricingPath.A_ETH_USD_B, tokenIn: tokens.FXS, tokenOut: tokens.BOND }, // IN (tokenB) => ETH, USD => OUT (tokenA)
      { path: PricingPath.A_ETH_USD_B, tokenIn: tokens.BOND, tokenOut: tokens.FXS }, // IN (tokenA) => USD, ETH => OUT (tokenB) 
    ],
    [
      // TOKEN_USD_BTC_WBTC
      // Note: Assumes WBTC/USD feed does not exist
      { path: PricingPath.TOKEN_USD_BTC_WBTC, tokenIn: tokens.WBTC, tokenOut: tokens.CHAINLINK_USD }, // IN (tokenA) => BTC, OUT is USD
      { path: PricingPath.TOKEN_USD_BTC_WBTC, tokenIn: tokens.WBTC, tokenOut: tokens.CHAINLINK_BTC }, // IN (tokenA) => BTC, OUT is BTC
      { path: PricingPath.TOKEN_USD_BTC_WBTC, tokenIn: tokens.WBTC, tokenOut: tokens.WETH }, // IN (tokenA) => BTC, OUT is ETH (tokenB)
      { path: PricingPath.TOKEN_USD_BTC_WBTC, tokenIn: tokens.WETH, tokenOut: tokens.WBTC }, // IN (tokenB) is ETH, BTC => OUT (tokenA)
      { path: PricingPath.TOKEN_USD_BTC_WBTC, tokenIn: tokens.DAI, tokenOut: tokens.WBTC }, // IN (tokenB) => USD, BTC => OUT (tokenA)
      { path: PricingPath.TOKEN_USD_BTC_WBTC, tokenIn: tokens.WBTC, tokenOut: tokens.USDC }, // IN (tokenA) => BTC, USD => OUT (tokenB)
      { path: PricingPath.TOKEN_USD_BTC_WBTC, tokenIn: tokens.WBTC, tokenOut: tokens.BNT }, // IN (tokenA) => USD,  BTC => OUT (tokenB)
    ]
  ];
}

describe('ChainlinkAdapter', () => {
  async function deploy() {
    const [deployer] = await ethers.getSigners();

    const implementation = await new ChainlinkAdapter__factory(deployer).deploy(
      tokens.WETH.address,
      tokens.WBTC.address,
    );

    await implementation.deployed();

    const proxy = await new ProxyUpgradeableOwnable__factory(deployer).deploy(
      implementation.address,
    );

    await proxy.deployed();

    const instance = ChainlinkAdapter__factory.connect(proxy.address, deployer);

    await instance.batchRegisterFeedMappings(feeds);

    return { deployer, instance };
  }

  async function deployStub() {
    const { deployer, instance } = await deploy();

    const stub = await new ChainlinkOraclePriceStub__factory(deployer).deploy();

    const stubCoin = bnToAddress(BigNumber.from(100));

    await instance.batchRegisterFeedMappings([
      {
        token: stubCoin,
        denomination: tokens.CHAINLINK_USD.address,
        feed: stub.address,
      },
    ]);

    await instance.upsertPair(stubCoin, tokens.CHAINLINK_USD.address);

    return { deployer, instance, stub, stubCoin };
  }

  describe('#upsertPair', () => {
    it('should only emit UpdatedPathForPair when path is updated', async () => {
      const { instance } = await loadFixture(deploy);

      await expect(
        instance.upsertPair(tokens.WETH.address, tokens.DAI.address),
      ).to.emit(instance, 'UpdatedPathForPair');

      let [isCached, _] = await instance.isPairSupported(
        tokens.WETH.address,
        tokens.DAI.address,
      );

      expect(isCached).to.be.true;

      await expect(
        instance.upsertPair(tokens.WETH.address, tokens.DAI.address),
      ).to.not.emit(instance, 'UpdatedPathForPair');

      [isCached, _] = await instance.isPairSupported(
        tokens.WETH.address,
        tokens.DAI.address,
      );

      expect(isCached).to.be.true;

      await instance.batchRegisterFeedMappings([
        {
          token: tokens.DAI.address,
          denomination: tokens.CHAINLINK_ETH.address,
          feed: bnToAddress(BigNumber.from(0)),
        },
      ]);

      await expect(
        instance.upsertPair(tokens.WETH.address, tokens.DAI.address),
      ).to.emit(instance, 'UpdatedPathForPair');

      [isCached, _] = await instance.isPairSupported(
        tokens.WETH.address,
        tokens.DAI.address,
      );
    });
  });

  for (let i = 0; i < paths.length; i++) {
    describe(`${PricingPath[paths[i][0].path]}`, () => {
      for (const { path, tokenIn, tokenOut } of paths[i]) {
        let instance: ChainlinkAdapter;

        describe(`${tokenIn.symbol}-${tokenOut.symbol}`, () => {
          beforeEach(async () => {
            const f = await loadFixture(deploy);
            instance = f.instance;

            if (
              path == PricingPath.TOKEN_USD ||
              path == PricingPath.TOKEN_USD_TOKEN ||
              path == PricingPath.A_USD_ETH_B
            ) {
              await instance.batchRegisterFeedMappings([
                {
                  token: tokens.WBTC.address,
                  denomination: tokens.CHAINLINK_USD.address,
                  feed: '0xf4030086522a5beea4988f8ca5b36dbc97bee88c', // maps WBTC/USD to BTC/USD feed on Ethereum mainnet
                },
              ]);
            }

            await instance.upsertPair(tokenIn.address, tokenOut.address);
          });

          describe('#isPairSupported', () => {
            it('should return true if pair is cached and path exists', async () => {
              const [isCached, hasPath] = await instance.isPairSupported(
                tokenIn.address,
                tokenOut.address,
              );

              expect(isCached).to.be.true;
              expect(hasPath).to.be.true;
            });
          });

          describe('#pricingPath', () => {
            it('should return pricing path for pair', async () => {
              const path1 = await instance.pricingPath(
                tokenIn.address,
                tokenOut.address,
              );

              const path2 = await instance.pricingPath(
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

              let networks = { tokenIn: 'ethereum', tokenOut: 'ethereum' };

              const quote = await instance.quote(
                _tokenIn.address,
                _tokenOut.address,
              );

              if (tokenIn.symbol === tokens.CHAINLINK_ETH.symbol) {
                networks.tokenIn = 'coingecko';
                _tokenIn.address = 'ethereum';
              }

              if (tokenOut.symbol === tokens.CHAINLINK_ETH.symbol) {
                networks.tokenOut = 'coingecko';
                _tokenOut.address = 'ethereum';
              }

              if (tokenIn.symbol === tokens.CHAINLINK_BTC.symbol) {
                networks.tokenIn = 'coingecko';
                _tokenIn.address = 'bitcoin';
              }

              if (tokenOut.symbol === tokens.CHAINLINK_BTC.symbol) {
                networks.tokenOut = 'coingecko';
                _tokenOut.address = 'bitcoin';
              }

              const coingeckoPrice = await getPriceBetweenTokens(
                networks,
                _tokenIn,
                _tokenOut,
              );

              const expected = convertPriceToBigNumberWithDecimals(
                coingeckoPrice,
                18,
              );

              validateQuote(3, quote, expected);
            });
          });

          describe('#quoteFrom', async () => {
            it('should return quote for pair from target', async () => {
              let _tokenIn = Object.assign({}, tokenIn);
              let _tokenOut = Object.assign({}, tokenOut);

              let networks = { tokenIn: 'ethereum', tokenOut: 'ethereum' };

              const quoteFrom = await instance.quoteFrom(
                _tokenIn.address,
                _tokenOut.address,
                target,
              );

              if (tokenIn.symbol === tokens.CHAINLINK_ETH.symbol) {
                networks.tokenIn = 'coingecko';
                _tokenIn.address = 'ethereum';
              }

              if (tokenOut.symbol === tokens.CHAINLINK_ETH.symbol) {
                networks.tokenOut = 'coingecko';
                _tokenOut.address = 'ethereum';
              }

              if (tokenIn.symbol === tokens.CHAINLINK_BTC.symbol) {
                networks.tokenIn = 'coingecko';
                _tokenIn.address = 'bitcoin';
              }

              if (tokenOut.symbol === tokens.CHAINLINK_BTC.symbol) {
                networks.tokenOut = 'coingecko';
                _tokenOut.address = 'bitcoin';
              }

              const coingeckoPrice = await getPriceBetweenTokens(
                networks,
                _tokenIn,
                _tokenOut,
                target,
              );

              const expected = convertPriceToBigNumberWithDecimals(
                coingeckoPrice,
                18,
              );

              validateQuote(3, quoteFrom, expected);
            });
          });
        });
      }
    });
  }
});
