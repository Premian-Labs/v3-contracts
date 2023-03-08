import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {
  IUniswapV3Pool__factory,
  UniswapV3Adapter,
  UniswapV3Adapter__factory,
  UniswapV3AdapterProxy__factory,
} from '../../typechain';

import {
  convertPriceToBigNumberWithDecimals,
  getPriceBetweenTokens,
  validateQuote,
} from '../../utils/defillama';

import { ONE_ETHER } from '../../utils/constants';
import {
  increase,
  revertToSnapshotAfterEach,
  setBlockNumber,
} from '../../utils/time';
import { UNISWAP_V3_FACTORY, Token, tokens } from '../../utils/addresses';

import { bnToAddress } from '@solidstate/library';

const { API_KEY_ALCHEMY } = process.env;
const jsonRpcUrl = `https://eth-mainnet.alchemyapi.io/v2/${API_KEY_ALCHEMY}`;
const blockNumber = 16600000; // Fri Feb 10 2023 17:59:11 GMT+0000
const target = 1676016000; // Fri Feb 10 2023 08:00:00 GMT+0000

const period = 600;
const cardinalityPerMinute = 4;

let pools: { tokenIn: Token; tokenOut: Token }[];

// prettier-ignore
{
  pools = [
    {tokenIn: tokens.WETH, tokenOut: tokens.WBTC}, 
    {tokenIn: tokens.WBTC, tokenOut: tokens.WETH}, 
    {tokenIn: tokens.WBTC, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.WETH, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.USDC, tokenOut: tokens.WETH}, 
    {tokenIn: tokens.WETH, tokenOut: tokens.DAI}, 
    {tokenIn: tokens.MKR, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.BOND, tokenOut: tokens.WETH}, 
    {tokenIn: tokens.USDT, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.DAI, tokenOut: tokens.USDC}, 
    {tokenIn: tokens.FXS, tokenOut: tokens.FRAX}, 
    {tokenIn: tokens.FRAX, tokenOut: tokens.FXS}, 
    {tokenIn: tokens.FRAX, tokenOut: tokens.USDT}, 
    {tokenIn: tokens.UNI, tokenOut: tokens.USDT}, 
    {tokenIn: tokens.LINK, tokenOut: tokens.UNI}, 
    {tokenIn: tokens.MATIC, tokenOut: tokens.WETH}, 
  ]
}

describe('UniswapV3Adapter', () => {
  let deployer: SignerWithAddress;
  let notOwner: SignerWithAddress;
  let instance: UniswapV3Adapter;

  before(async () => {
    await setBlockNumber(jsonRpcUrl, blockNumber);
  });

  revertToSnapshotAfterEach(async () => {
    [deployer, notOwner] = await ethers.getSigners();

    const implementation = await new UniswapV3Adapter__factory(deployer).deploy(
      UNISWAP_V3_FACTORY,
    );

    await implementation.deployed();

    const proxy = await new UniswapV3AdapterProxy__factory(deployer).deploy(
      implementation.address,
    );

    await proxy.deployed();

    instance = UniswapV3Adapter__factory.connect(proxy.address, deployer);

    await instance.setPeriod(period);
    await instance.setCardinalityPerMinute(cardinalityPerMinute);
  });

  describe('#isPairSupported', () => {
    it('should return false if pair is not supported by adapter', async () => {
      const [isCached, _] = await instance.isPairSupported(
        tokens.WETH.address,
        tokens.DAI.address,
      );

      expect(isCached).to.be.false;
    });

    it('should return false if path for pair does not exist', async () => {
      const [_, hasPath] = await instance.isPairSupported(
        tokens.WETH.address,
        bnToAddress(BigNumber.from(0)),
      );

      expect(hasPath).to.be.false;
    });
  });

  describe('#upsertPair', () => {
    it('should revert if pair cannot be supported', async () => {
      await expect(
        instance.upsertPair(
          bnToAddress(BigNumber.from(0)),
          tokens.WETH.address,
        ),
      ).to.be.revertedWithCustomError(
        instance,
        'OracleAdapter__PairCannotBeSupported',
      );

      await expect(
        instance.upsertPair(
          tokens.WBTC.address,
          bnToAddress(BigNumber.from(0)),
        ),
      ).to.be.revertedWithCustomError(
        instance,
        'OracleAdapter__PairCannotBeSupported',
      );
    });

    it('should not fail if called multiple times for same pair', async () => {
      await instance.upsertPair(tokens.WETH.address, tokens.DAI.address);

      const [isCached, _] = await instance.isPairSupported(
        tokens.WETH.address,
        tokens.DAI.address,
      );

      expect(isCached).to.be.true;

      expect(
        await instance.upsertPair(tokens.WETH.address, tokens.DAI.address),
      );
    });
  });

  describe('#quote', async () => {
    it('should revert if pair is not supported', async () => {
      await expect(
        instance.quote(tokens.WETH.address, bnToAddress(BigNumber.from(0))),
      ).to.be.revertedWithCustomError(
        instance,
        'OracleAdapter__PairNotSupported',
      );
    });

    it('should revert if observation cardinality must be increased', async () => {
      await instance.setCardinalityPerMinute(20);

      await expect(
        instance.quote(tokens.WETH.address, tokens.DAI.address),
      ).to.be.revertedWithCustomError(
        instance,
        'UniswapV3Adapter__ObservationCardinalityTooLow',
      );
    });

    it('should find path if pair has not been added', async () => {
      // must increase cardinality to 121 for pools
      await IUniswapV3Pool__factory.connect(
        '0xc2e9f25be6257c210d7adf0d4cd6e3e881ba25f8',
        deployer,
      ).increaseObservationCardinalityNext(121);

      await IUniswapV3Pool__factory.connect(
        '0x60594a405d53811d3bc4766596efd80fd545a270',
        deployer,
      ).increaseObservationCardinalityNext(121);

      await IUniswapV3Pool__factory.connect(
        '0xa80964c5bbd1a0e95777094420555fead1a26c1e',
        deployer,
      ).increaseObservationCardinalityNext(121);

      expect(await instance.quote(tokens.WETH.address, tokens.DAI.address));
    });

    it('should return quote using correct denomination', async () => {
      let tokenIn = tokens.WETH;
      let tokenOut = tokens.DAI;

      await instance.upsertPair(tokenIn.address, tokenOut.address);

      let quote = await instance.quote(tokenIn.address, tokenOut.address);

      let invertedQuote = await instance.quote(
        tokenOut.address,
        tokenIn.address,
      );

      expect(quote.div(ONE_ETHER)).to.be.eq(ONE_ETHER.div(invertedQuote));

      tokenIn = tokens.WETH;
      tokenOut = tokens.USDC;

      await instance.upsertPair(tokenIn.address, tokenOut.address);

      quote = await instance.quote(tokenIn.address, tokenOut.address);
      invertedQuote = await instance.quote(tokenOut.address, tokenIn.address);

      expect(quote.div(ONE_ETHER)).to.be.eq(ONE_ETHER.div(invertedQuote));

      tokenIn = tokens.WBTC;
      tokenOut = tokens.USDC;

      await instance.upsertPair(tokenIn.address, tokenOut.address);

      quote = await instance.quote(tokenIn.address, tokenOut.address);
      invertedQuote = await instance.quote(tokenOut.address, tokenIn.address);

      expect(quote.div(ONE_ETHER)).to.be.eq(ONE_ETHER.div(invertedQuote));
    });
  });

  describe('#quoteFrom', () => {
    beforeEach(async () => {
      await setBlockNumber(jsonRpcUrl, 16597040);

      [deployer] = await ethers.getSigners();

      const implementation = await new UniswapV3Adapter__factory(
        deployer,
      ).deploy(UNISWAP_V3_FACTORY);

      await implementation.deployed();

      const proxy = await new UniswapV3AdapterProxy__factory(deployer).deploy(
        implementation.address,
      );

      await proxy.deployed();

      instance = UniswapV3Adapter__factory.connect(proxy.address, deployer);

      await instance.setPeriod(600);
      await instance.setCardinalityPerMinute(4);
    });

    after(async () => {
      await setBlockNumber(jsonRpcUrl, blockNumber);
    });

    it('should revert if the oldest observation is less the TWAP period', async () => {
      await instance.upsertPair(tokens.UNI.address, tokens.AAVE.address);

      await expect(
        instance.quoteFrom(tokens.UNI.address, tokens.AAVE.address, target),
      ).to.be.revertedWithCustomError(
        instance,
        'UniswapV3Adapter__InsufficientObservationPeriod',
      );

      // oldest observation is ~490 seconds
      // fast-forward so that the oldest observation is >= 600 seconds
      await increase(120);

      expect(
        await instance.quoteFrom(
          tokens.UNI.address,
          tokens.AAVE.address,
          target,
        ),
      );
    });
  });

  describe('#poolsForPair', () => {
    it('should return pools for pair', async () => {
      let pools = await instance.poolsForPair(
        tokens.WETH.address,
        tokens.DAI.address,
      );

      expect(pools.length).to.be.eq(0);

      await instance.upsertPair(tokens.WETH.address, tokens.DAI.address);

      pools = await instance.poolsForPair(
        tokens.WETH.address,
        tokens.DAI.address,
      );

      expect(pools).to.be.deep.eq([
        '0xc2e9f25be6257c210d7adf0d4cd6e3e881ba25f8',
        '0x60594a405d53811d3bc4766596efd80fd545a270',
        '0xa80964c5bbd1a0e95777094420555fead1a26c1e',
      ]);
    });
  });

  describe('#factory', () => {
    it('should return correct UniswapV3 factory address', async () => {
      expect(await instance.factory()).to.be.eq(UNISWAP_V3_FACTORY);
    });
  });

  describe('#period', () =>
    it('should return correct period', async () => {
      expect(await instance.period()).to.be.eq(period);
    }));

  describe('#cardinalityPerMinute', () => {
    it('should return correct cardinality per minute', async () => {
      expect(await instance.cardinalityPerMinute()).to.be.eq(
        cardinalityPerMinute,
      );
    });
  });

  describe('#gasPerCardinality', () => {
    it('should return correct gas per cardinality', async () => {
      expect(await instance.gasPerCardinality()).to.be.eq(22250);
    });
  });

  describe('#gasCostToSupportPool', () => {
    it('should return correct gas cost to add support for a new pool', async () => {
      expect(await instance.gasCostToSupportPool()).to.be.eq(30000);
    });
  });

  describe('#supportedFeeTiers', () => {
    it('should return supported fee tiers', async () => {
      const feeTiers = await instance.supportedFeeTiers();
      expect(feeTiers).to.be.deep.eq([500, 3000, 10000]);
    });
  });

  describe('#setPeriod', () => {
    const newPeriod = 800;

    it('should revert if not called by owner', async () => {
      await expect(
        instance.connect(notOwner).setPeriod(newPeriod),
      ).to.be.revertedWithCustomError(instance, 'Ownable__NotOwner');
    });

    it('should set period to new value', async () => {
      await instance.setPeriod(newPeriod);
      expect(await instance.period()).to.be.eq(newPeriod);
    });
  });

  describe('#setCardinalityPerMinute', () => {
    const newCardinalityPerMinute = 8;

    it('should revert if not called by owner', async () => {
      await expect(
        instance
          .connect(notOwner)
          .setCardinalityPerMinute(newCardinalityPerMinute),
      ).to.be.revertedWithCustomError(instance, 'Ownable__NotOwner');
    });

    it('should set cardinality per minute to new value', async () => {
      await instance.setCardinalityPerMinute(newCardinalityPerMinute);
      expect(await instance.cardinalityPerMinute()).to.be.eq(
        newCardinalityPerMinute,
      );
    });
  });

  describe('#setGasPerCardinality', () => {
    const newGasPerCardinality = 10000;

    it('should revert if not called by owner', async () => {
      await expect(
        instance.connect(notOwner).setGasPerCardinality(newGasPerCardinality),
      ).to.be.revertedWithCustomError(instance, 'Ownable__NotOwner');
    });

    it('should revert if gas per cardinality is 0', async () => {
      await expect(
        instance.setGasPerCardinality(0),
      ).to.be.revertedWithCustomError(
        instance,
        'UniswapV3Adapter__InvalidGasPerCardinality',
      );
    });

    it('should set gas per cardinality to new value', async () => {
      await instance.setGasPerCardinality(newGasPerCardinality);
      expect(await instance.gasPerCardinality()).to.be.eq(newGasPerCardinality);
    });
  });

  describe('#setGasCostToSupportPool', () => {
    const newGasToSupportPool = 15000;

    it('should revert if not called by owner', async () => {
      await expect(
        instance.connect(notOwner).setGasCostToSupportPool(newGasToSupportPool),
      ).to.be.revertedWithCustomError(instance, 'Ownable__NotOwner');
    });

    it('should revert if gas cost to support pool is 0', async () => {
      await expect(
        instance.setGasCostToSupportPool(0),
      ).to.be.revertedWithCustomError(
        instance,
        'UniswapV3Adapter__InvalidGasCostToSupportPool',
      );
    });

    it('should set gas cost to support pool to new value', async () => {
      await instance.setGasCostToSupportPool(newGasToSupportPool);
      expect(await instance.gasCostToSupportPool()).to.be.eq(
        newGasToSupportPool,
      );
    });
  });

  describe('#insertFeeTier', () => {
    const newFeeTier = 100;

    it('should revert if not called by owner', async () => {
      await expect(
        instance.connect(notOwner).insertFeeTier(newFeeTier),
      ).to.be.revertedWithCustomError(instance, 'Ownable__NotOwner');
    });

    it('should revert if fee tier is invalid', async () => {
      await expect(instance.insertFeeTier(15000)).to.be.revertedWithCustomError(
        instance,
        'UniswapV3Adapter__InvalidFeeTier',
      );
    });

    it('should revert if fee tier exists', async () => {
      await expect(instance.insertFeeTier(10000)).to.be.revertedWithCustomError(
        instance,
        'UniswapV3Adapter__FeeTierExists',
      );
    });

    it('should successfully add new fee tier', async () => {
      await instance.insertFeeTier(100);
      const feeTiers = await instance.supportedFeeTiers();
      expect(feeTiers).to.be.deep.eq([500, 3000, 10000, 100]);
    });
  });

  for (let i = 0; i < pools.length; i++) {
    const { tokenIn, tokenOut } = pools[i];

    describe(`${tokenIn.symbol}-${tokenOut.symbol}`, () => {
      beforeEach(async () => {
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
