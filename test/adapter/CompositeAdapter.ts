import {
  ChainlinkAdapter__factory,
  ChainlinkAdapterProxy__factory,
  UniswapV3Adapter__factory,
  UniswapV3AdapterProxy__factory,
  CompositeAdapter,
  CompositeAdapter__factory,
  CompositeAdapterProxy__factory,
} from '../../typechain';
import {
  UNISWAP_V3_FACTORY,
  feeds,
  Token,
  tokens,
} from '../../utils/addresses';
import {
  convertPriceToBigNumberWithDecimals,
  getPriceBetweenTokens,
  validateQuote,
} from '../../utils/defillama';

import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { bnToAddress } from '@solidstate/library';
import { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';

const period = 600;
const cardinalityPerMinute = 4;

const target = 1676016000; // Fri Feb 10 2023 08:00:00 GMT+0000

let pairs: { tokenIn: Token; tokenOut: Token }[];

// prettier-ignore
{
  pairs = [
    {tokenIn: tokens.WBTC, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.WBTC, tokenOut: tokens.USDT}, 
    {tokenIn: tokens.WBTC, tokenOut: tokens.DAI}, 
    {tokenIn: tokens.MKR, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.MKR, tokenOut: tokens.ENS}, 
    {tokenIn: tokens.USDT, tokenOut: tokens.DAI}, 
    {tokenIn: tokens.USDT, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.DAI, tokenOut: tokens.USDC},
    {tokenIn: tokens.DAI, tokenOut: tokens.LINK},
    {tokenIn: tokens.UNI, tokenOut: tokens.USDT}, 
    {tokenIn: tokens.LINK, tokenOut: tokens.UNI}, 
    {tokenIn: tokens.MATIC, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.BIT, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.GNO, tokenOut: tokens.LINK}, 
    {tokenIn: tokens.LOOKS, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.LOOKS, tokenOut: tokens.WBTC}, 
  ]
}

describe('CompositeAdapter', () => {
  async function deploy() {
    const [deployer] = await ethers.getSigners();

    const chainlinkImplementation = await new ChainlinkAdapter__factory(
      deployer,
    ).deploy(tokens.WETH.address, tokens.WBTC.address);

    await chainlinkImplementation.deployed();

    const chainlinkProxy = await new ChainlinkAdapterProxy__factory(
      deployer,
    ).deploy(chainlinkImplementation.address);

    await chainlinkProxy.deployed();

    const chainlinkInstance = ChainlinkAdapter__factory.connect(
      chainlinkProxy.address,
      deployer,
    );

    await chainlinkInstance.batchRegisterFeedMappings(feeds);

    const uniswapImplementation = await new UniswapV3Adapter__factory(
      deployer,
    ).deploy(UNISWAP_V3_FACTORY, tokens.WETH.address, 22250, 30000);

    await uniswapImplementation.deployed();

    const uniswapProxy = await new UniswapV3AdapterProxy__factory(
      deployer,
    ).deploy(cardinalityPerMinute, period, uniswapImplementation.address);

    await uniswapProxy.deployed();

    const uniswapInstance = UniswapV3Adapter__factory.connect(
      uniswapProxy.address,
      deployer,
    );

    await uniswapInstance.setPeriod(period);
    await uniswapInstance.setCardinalityPerMinute(cardinalityPerMinute);

    const implementation = await new CompositeAdapter__factory(deployer).deploy(
      chainlinkProxy.address,
      uniswapProxy.address,
      tokens.WETH.address,
    );

    await implementation.deployed();

    const proxy = await new CompositeAdapterProxy__factory(deployer).deploy(
      implementation.address,
    );

    await proxy.deployed();

    const instance = CompositeAdapter__factory.connect(proxy.address, deployer);

    return { deployer, instance };
  }

  describe('#isPairSupported', () => {
    it('should revert if token is wrapped native token', async () => {
      const { instance } = await loadFixture(deploy);

      await expect(
        instance.isPairSupported(tokens.WETH.address, tokens.DAI.address),
      ).to.be.revertedWithCustomError(
        instance,
        'CompositeAdapter__TokenCannotBeWrappedNative',
      );

      await expect(
        instance.isPairSupported(tokens.DAI.address, tokens.WETH.address),
      ).to.be.revertedWithCustomError(
        instance,
        'CompositeAdapter__TokenCannotBeWrappedNative',
      );
    });

    it('should return false if pair is not supported by adapter', async () => {
      const { instance } = await loadFixture(deploy);

      let [isCached, _] = await instance.isPairSupported(
        bnToAddress(BigNumber.from(1)),
        tokens.DAI.address,
      );

      expect(isCached).to.be.false;

      [isCached, _] = await instance.isPairSupported(
        tokens.DAI.address,
        bnToAddress(BigNumber.from(1)),
      );

      expect(isCached).to.be.false;
    });

    it('should return false if path for pair does not exist', async () => {
      const { instance } = await loadFixture(deploy);

      let [_, hasPath] = await instance.isPairSupported(
        bnToAddress(BigNumber.from(1)),
        tokens.DAI.address,
      );

      expect(hasPath).to.be.false;

      [_, hasPath] = await instance.isPairSupported(
        tokens.DAI.address,
        bnToAddress(BigNumber.from(1)),
      );

      expect(hasPath).to.be.false;
    });
  });

  describe('#upsertPair', () => {
    it('should revert if token is wrapped native token', async () => {
      const { instance } = await loadFixture(deploy);

      await expect(
        instance.upsertPair(tokens.WETH.address, tokens.DAI.address),
      ).to.be.revertedWithCustomError(
        instance,
        'CompositeAdapter__TokenCannotBeWrappedNative',
      );

      await expect(
        instance.upsertPair(tokens.DAI.address, tokens.WETH.address),
      ).to.be.revertedWithCustomError(
        instance,
        'CompositeAdapter__TokenCannotBeWrappedNative',
      );
    });

    it('should revert if pair cannot be supported', async () => {
      const { instance } = await loadFixture(deploy);

      await expect(
        instance.upsertPair(bnToAddress(BigNumber.from(1)), tokens.DAI.address),
      ).to.be.revertedWithCustomError(
        instance,
        'OracleAdapter__PairCannotBeSupported',
      );

      await expect(
        instance.upsertPair(tokens.DAI.address, bnToAddress(BigNumber.from(1))),
      ).to.be.revertedWithCustomError(
        instance,
        'OracleAdapter__PairCannotBeSupported',
      );
    });

    it('should upsert pair if pair is not already cached in upstream adapters', async () => {
      const { instance } = await loadFixture(deploy);

      let tokenA = tokens.EUL.address;
      let tokenB = tokens.DAI.address;

      let [isCached, _] = await instance.isPairSupported(tokenA, tokenB);

      expect(isCached).to.be.false;

      await instance.upsertPair(tokenA, tokenB);

      [isCached, _] = await instance.isPairSupported(tokenA, tokenB);

      expect(isCached).to.be.true;
    });
  });

  describe('#quote', async () => {
    it('should revert if token is wrapped native token', async () => {
      const { instance } = await loadFixture(deploy);

      await expect(
        instance.quote(tokens.WETH.address, tokens.DAI.address),
      ).to.be.revertedWithCustomError(
        instance,
        'CompositeAdapter__TokenCannotBeWrappedNative',
      );

      await expect(
        instance.quote(tokens.DAI.address, tokens.WETH.address),
      ).to.be.revertedWithCustomError(
        instance,
        'CompositeAdapter__TokenCannotBeWrappedNative',
      );
    });

    it('should revert if pair cannot be supported', async () => {
      const { instance } = await loadFixture(deploy);

      await expect(
        instance.quote(bnToAddress(BigNumber.from(1)), tokens.DAI.address),
      ).to.be.revertedWithCustomError(
        instance,
        'OracleAdapter__PairCannotBeSupported',
      );

      await expect(
        instance.quote(tokens.DAI.address, bnToAddress(BigNumber.from(1))),
      ).to.be.revertedWithCustomError(
        instance,
        'OracleAdapter__PairCannotBeSupported',
      );
    });
  });

  describe('#quoteFrom', async () => {
    it('should revert if token is wrapped native token', async () => {
      const { instance } = await loadFixture(deploy);

      await expect(
        instance.quoteFrom(tokens.WETH.address, tokens.DAI.address, target),
      ).to.be.revertedWithCustomError(
        instance,
        'CompositeAdapter__TokenCannotBeWrappedNative',
      );

      await expect(
        instance.quoteFrom(tokens.DAI.address, tokens.WETH.address, target),
      ).to.be.revertedWithCustomError(
        instance,
        'CompositeAdapter__TokenCannotBeWrappedNative',
      );
    });

    it('should revert if target is zero', async () => {
      const { instance } = await loadFixture(deploy);

      await expect(
        instance.quoteFrom(tokens.EUL.address, tokens.DAI.address, 0),
      ).to.be.revertedWithCustomError(instance, 'OracleAdapter__InvalidTarget');
    });

    it('should revert if pair cannot be supported', async () => {
      const { instance } = await loadFixture(deploy);

      await expect(
        instance.quoteFrom(
          bnToAddress(BigNumber.from(1)),
          tokens.DAI.address,
          target,
        ),
      ).to.be.revertedWithCustomError(
        instance,
        'OracleAdapter__PairCannotBeSupported',
      );

      await expect(
        instance.quoteFrom(
          tokens.DAI.address,
          bnToAddress(BigNumber.from(1)),
          target,
        ),
      ).to.be.revertedWithCustomError(
        instance,
        'OracleAdapter__PairCannotBeSupported',
      );
    });
  });

  // TODO: Add after merging #146
  describe.skip('#describePricingPath', () => {});

  for (let i = 0; i < pairs.length; i++) {
    const { tokenIn, tokenOut } = pairs[i];
    let instance: CompositeAdapter;

    describe(`${tokenIn.symbol}-${tokenOut.symbol}`, () => {
      beforeEach(async () => {
        const f = await loadFixture(deploy);
        instance = f.instance;
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

      describe('#quote', async () => {
        it('should return quote for pair', async () => {
          let _tokenIn = Object.assign({}, tokenIn);
          let _tokenOut = Object.assign({}, tokenOut);

          let networks = { tokenIn: 'ethereum', tokenOut: 'ethereum' };

          const quote = await instance.quote(
            _tokenIn.address,
            _tokenOut.address,
          );

          const coingeckoPrice = await getPriceBetweenTokens(
            networks,
            _tokenIn,
            _tokenOut,
          );

          const expected = convertPriceToBigNumberWithDecimals(
            coingeckoPrice,
            18,
          );

          validateQuote(2, quote, expected);
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

          validateQuote(2, quoteFrom, expected);
        });
      });
    });
  }
});