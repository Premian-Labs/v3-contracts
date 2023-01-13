import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import {
  ERC20Mock,
  ERC20Mock__factory,
  IPoolMock,
  IPoolMock__factory,
} from '../../typechain';
import { BigNumber } from 'ethers';
import { parseEther } from 'ethers/lib/utils';
import { PoolUtil } from '../../utils/PoolUtil';
import {
  deployMockContract,
  MockContract,
} from '@ethereum-waffle/mock-contract';
import { ONE_MONTH } from '../../utils/constants';
import { now, revertToSnapshotAfterEach } from '../../utils/time';

describe('Pool', () => {
  let deployer: SignerWithAddress;
  let lp: SignerWithAddress;

  let callPool: IPoolMock;
  let putPool: IPoolMock;
  let p: PoolUtil;

  let base: ERC20Mock;
  let underlying: ERC20Mock;
  let baseOracle: MockContract;
  let underlyingOracle: MockContract;

  let strike = 1000;
  let maturity: number;

  let isCall: boolean;
  let collateral: BigNumber;

  let WAD = parseEther('1');

  before(async () => {
    [deployer, lp] = await ethers.getSigners();

    p = await PoolUtil.deploy(deployer, true, true);

    underlying = await new ERC20Mock__factory(deployer).deploy('WETH', 18);
    base = await new ERC20Mock__factory(deployer).deploy('USDC', 6);

    await underlying.mint(lp.address, parseEther('1000000'));
    await base.mint(lp.address, parseEther('1000'));

    baseOracle = await deployMockContract(deployer as any, [
      'function latestAnswer () external view returns (int)',
      'function decimals () external view returns (uint8)',
    ]);

    underlyingOracle = await deployMockContract(deployer as any, [
      'function latestAnswer () external view returns (int)',
      'function decimals () external view returns (uint8)',
    ]);

    maturity = (await now()) + ONE_MONTH;

    for (isCall of [true, false]) {
      const tx = await p.poolFactory.deployPool(
        base.address,
        underlying.address,
        baseOracle.address,
        underlyingOracle.address,
        strike,
        maturity,
        isCall,
      );

      const r = await tx.wait(1);
      const poolAddress = (r as any).events[0].args.poolAddress;

      if (isCall) {
        callPool = IPoolMock__factory.connect(poolAddress, deployer);
        collateral = parseEther('10');
      } else {
        putPool = IPoolMock__factory.connect(poolAddress, deployer);
        collateral = parseEther('1000');
      }
    }
  });

  revertToSnapshotAfterEach(async () => {});

  describe('#formatTokenId(address,uint256,uint256,Position.OrderType)', () => {
    it('should properly format token id', async () => {
      const operator = '0x1000000000000000000000000000000000000001';
      const tokenId = await callPool.formatTokenId(
        operator,
        parseEther('0.001'),
        parseEther('1'),
        3,
      );

      console.log(tokenId.toHexString());

      expect(tokenId.mask(10)).to.eq(1);
      expect(tokenId.shr(10).mask(10)).to.eq(1000);
      expect(tokenId.shr(20).mask(160)).to.eq(operator);
      expect(tokenId.shr(180).mask(4)).to.eq(3);
      expect(tokenId.shr(252).mask(4)).to.eq(1);
    });
  });

  describe('#parseTokenId(uint256)', () => {
    it('should properly parse token id', async () => {
      const r = await callPool.parseTokenId(
        BigNumber.from(
          '0x10000000000000000031000000000000000000000000000000000000001fa001',
        ),
      );

      expect(r.lower).to.eq(parseEther('0.001'));
      expect(r.upper).to.eq(parseEther('1'));
      expect(r.operator).to.eq('0x1000000000000000000000000000000000000001');
      expect(r.orderType).to.eq(3);
      expect(r.version).to.eq(1);
    });
  });

  describe('#fromPool(PoolStorage.Layout,bool)', () => {
    it('should return pool state', async () => {
      let isBuy = true;
      let args = await callPool.fromPool(isBuy);

      expect(args.liquidityRate).to.eq(0);
      expect(args.marketPrice).to.eq(0);
      expect(args.lower).to.eq(parseEther('0.001'));
      expect(args.upper).to.eq(parseEther('1'));
      expect(args.isBuy).to.eq(isBuy);

      args = await callPool.fromPool(!isBuy);

      expect(args.liquidityRate).to.eq(0);
      expect(args.marketPrice).to.eq(0);
      expect(args.lower).to.eq(parseEther('0.001'));
      expect(args.upper).to.eq(parseEther('1'));
      expect(args.isBuy).to.eq(!isBuy);

      let lower = parseEther('0.25');
      let upper = parseEther('0.75');

      let position = {
        lower: lower,
        upper: upper,
        operator: lp.address,
        owner: lp.address,
        orderType: 0,
        isCall: isCall,
        strike: strike,
      };

      await underlying.connect(lp).approve(callPool.address, collateral);

      await callPool
        .connect(lp)
        .deposit(
          position,
          await callPool.getNearestTickBelow(lower),
          await callPool.getNearestTickBelow(upper),
          collateral,
          0,
          0,
        );

      args = await callPool.fromPool(isBuy);

      expect(args.liquidityRate).to.eq(parseEther('4'));
      expect(args.marketPrice).to.eq(upper);
      expect(args.lower).to.eq(lower);
      expect(args.upper).to.eq(upper);
      expect(args.isBuy).to.eq(isBuy);

      args = await callPool.fromPool(!isBuy);

      expect(args.liquidityRate).to.eq(parseEther('4'));
      expect(args.marketPrice).to.eq(upper);
      expect(args.lower).to.eq(lower);
      expect(args.upper).to.eq(upper);
      expect(args.isBuy).to.eq(!isBuy);
    });
  });

  describe('#proportion(uint256,uint256,uint256)', () => {
    it('should return the proportional amount', async () => {
      for (const t of [
        [parseEther('0.25'), 0],
        [parseEther('0.75'), parseEther('1')],
        [parseEther('0.5'), parseEther('0.5')],
      ]) {
        expect(
          await callPool['proportion(uint256,uint256,uint256)'](
            parseEther('0.25'),
            parseEther('0.75'),
            t[0],
          ),
        ).to.eq(t[1]);
      }
    });

    it('should revert if lower >= upper', async () => {
      await expect(
        callPool['proportion(uint256,uint256,uint256)'](
          parseEther('0.75'),
          parseEther('0.25'),
          0,
        ),
      ).to.be.revertedWithCustomError(
        callPool,
        'Pricing__UpperNotGreaterThanLower',
      );
    });

    it('should revert if lower > market || market > upper', async () => {
      await expect(
        callPool['proportion(uint256,uint256,uint256)'](
          parseEther('0.25'),
          parseEther('0.75'),
          parseEther('0.2'),
        ),
      ).to.be.revertedWithCustomError(callPool, 'Pricing__PriceOutOfRange');

      await expect(
        callPool['proportion(uint256,uint256,uint256)'](
          parseEther('0.25'),
          parseEther('0.75'),
          parseEther('0.8'),
        ),
      ).to.be.revertedWithCustomError(callPool, 'Pricing__PriceOutOfRange');
    });
  });

  describe('#amountOfTicksBetween(uint256,uint256)', () => {
    it('should correctly calculate amount of ticks between two values', async () => {
      for (const t of [
        [parseEther('0.001'), parseEther('1'), 999],
        [parseEther('0.05'), parseEther('0.95'), 900],
        [parseEther('0.49'), parseEther('0.491'), 1],
      ]) {
        expect(await callPool.amountOfTicksBetween(t[0], t[1])).to.eq(t[2]);
      }
    });

    it('should revert if lower >= upper', async () => {
      for (const t of [
        [parseEther('0.2'), parseEther('0.01')],
        [parseEther('0.1'), parseEther('0.1')],
      ]) {
        await expect(
          callPool.amountOfTicksBetween(t[0], t[1]),
        ).to.be.revertedWithCustomError(
          callPool,
          'Pricing__UpperNotGreaterThanLower',
        );
      }
    });
  });

  describe('#liquidity(Pricing.Args)', () => {
    it('should return the liquidity', async () => {
      for (const t of [
        [
          parseEther('1'),
          parseEther('0.001'),
          parseEther('1'),
          parseEther('999'),
        ],
        [
          parseEther('5'),
          parseEther('0.05'),
          parseEther('0.95'),
          parseEther('4500'),
        ],
        [
          parseEther('10'),
          parseEther('0.49'),
          parseEther('0.491'),
          parseEther('10'),
        ],
      ]) {
        const args = {
          liquidityRate: t[0],
          marketPrice: 0,
          lower: t[1],
          upper: t[2],
          isBuy: true,
        };

        expect(await callPool.liquidity(args)).to.eq(t[3]);
      }
    });
  });

  describe('#bidLiquidity(Pricing.Args)', () => {
    it('should return the bid liquidity', async () => {
      let args = {
        liquidityRate: parseEther('1'),
        marketPrice: parseEther('0.25'), // price == lower
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: false,
      };

      expect(await callPool.bidLiquidity(args)).to.eq(0);

      args.marketPrice = mean(args.lower, args.upper); // price == mean(lower, upper)

      expect(await callPool.bidLiquidity(args)).to.eq(
        (await callPool.liquidity(args)).div(2),
      );

      args.marketPrice = parseEther('0.75'); // price == upper

      expect(await callPool.bidLiquidity(args)).to.eq(
        await callPool.liquidity(args),
      );
    });
  });

  describe('#askLiquidity(Pricing.Args)', () => {
    it('should return the ask liquidity', async () => {
      let args = {
        liquidityRate: parseEther('1'),
        marketPrice: parseEther('0.25'), // price == lower
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: true,
      };

      expect(await callPool.askLiquidity(args)).to.eq(
        await callPool.liquidity(args),
      );

      args.marketPrice = mean(args.lower, args.upper); // price == mean(lower, upper)

      expect(await callPool.askLiquidity(args)).to.eq(
        (await callPool.liquidity(args)).div(2),
      );

      args.marketPrice = parseEther('0.75'); // price == upper

      expect(await callPool.askLiquidity(args)).to.eq(0);
    });
  });

  describe('#maxTradeSize(Pricing.Args)', () => {
    it('should return the max trade size for buy order', async () => {
      let args = {
        liquidityRate: parseEther('1'),
        marketPrice: parseEther('0.75'), // price == upper
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: true,
      };

      expect(await callPool.maxTradeSize(args)).to.eq(
        await callPool.askLiquidity(args),
      );
    });

    it('should return the max trade size for sell order', async () => {
      let args = {
        liquidityRate: parseEther('1'),
        marketPrice: parseEther('0.75'), // price == upper
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: false,
      };

      expect(await callPool.maxTradeSize(args)).to.eq(
        await callPool.bidLiquidity(args),
      );
    });
  });

  describe('#price(Pricing.Args,uint256)', () => {
    it('should return upper tick for buy order if liquidity == 0', async () => {
      let args = {
        liquidityRate: 0,
        marketPrice: parseEther('0.5'),
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: true,
      };

      expect(await callPool.price(args, 0)).to.eq(args.upper);
    });

    it('should return lower tick for sell order if liquidity == 0', async () => {
      let args = {
        liquidityRate: 0,
        marketPrice: parseEther('0.5'),
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: false,
      };

      expect(await callPool.price(args, 0)).to.eq(args.lower);
    });

    it('should return the price when trade size == 0', async () => {
      let args = {
        liquidityRate: parseEther('1'),
        marketPrice: parseEther('0.5'),
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: true,
      };

      expect(await callPool.price(args, 0)).to.eq(args.lower);

      args.isBuy = false;

      expect(await callPool.price(args, 0)).to.eq(args.upper);
    });

    it('should return the price for buy order when liquidity > 0 && trade size > 0', async () => {
      let args = {
        liquidityRate: parseEther('1'),
        marketPrice: parseEther('0.75'),
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: true,
      };

      let liq = await callPool.liquidity(args);
      let askLiq = await callPool.askLiquidity(args);
      let bidLiq = await callPool.bidLiquidity(args);

      // price == upper
      // ask side liquidity == 0
      // bid side liquidity == liquidity

      expect(askLiq).to.eq(0);
      expect(bidLiq).to.eq(liq);

      expect(await callPool.price(args, askLiq)).to.eq(args.lower);
      expect(await callPool.price(args, bidLiq)).to.eq(args.upper);

      args.marketPrice = args.lower;

      liq = await callPool.liquidity(args);
      askLiq = await callPool.askLiquidity(args);
      bidLiq = await callPool.bidLiquidity(args);

      // price == lower
      // ask side liquidity == liquidity
      // bid side liquidity == 0

      expect(askLiq).to.eq(liq);
      expect(bidLiq).to.eq(0);

      expect(await callPool.price(args, askLiq)).to.eq(args.upper);
      expect(await callPool.price(args, bidLiq)).to.eq(args.lower);

      let _mean = mean(args.lower, args.upper);
      args.marketPrice = _mean;

      liq = await callPool.liquidity(args);
      askLiq = await callPool.askLiquidity(args);
      bidLiq = await callPool.bidLiquidity(args);

      // price == mean(lower, upper)
      // ask side liquidity == liquidity/2
      // bid side liquidity == liquidity/2

      expect(askLiq).to.eq(liq.div(2));
      expect(bidLiq).to.eq(liq.div(2));

      expect(await callPool.price(args, askLiq)).to.eq(_mean);
      expect(await callPool.price(args, bidLiq)).to.eq(_mean);
    });

    it('should return the price for sell order when liquidity > 0 && trade size > 0', async () => {
      let args = {
        liquidityRate: parseEther('1'),
        marketPrice: parseEther('0.75'),
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: false,
      };

      let liq = await callPool.liquidity(args);
      let askLiq = await callPool.askLiquidity(args);
      let bidLiq = await callPool.bidLiquidity(args);

      // price == upper
      // ask side liquidity == 0
      // bid side liquidity == liquidity

      expect(askLiq).to.eq(0);
      expect(bidLiq).to.eq(liq);

      expect(await callPool.price(args, askLiq)).to.eq(args.upper);
      expect(await callPool.price(args, bidLiq)).to.eq(args.lower);

      args.marketPrice = args.lower;

      liq = await callPool.liquidity(args);
      askLiq = await callPool.askLiquidity(args);
      bidLiq = await callPool.bidLiquidity(args);

      // price == lower
      // ask side liquidity == liquidity
      // bid side liquidity == 0

      expect(askLiq).to.eq(liq);
      expect(bidLiq).to.eq(0);

      expect(await callPool.price(args, askLiq)).to.eq(args.lower);
      expect(await callPool.price(args, bidLiq)).to.eq(args.upper);

      let _mean = mean(args.lower, args.upper);
      args.marketPrice = _mean;

      liq = await callPool.liquidity(args);
      askLiq = await callPool.askLiquidity(args);
      bidLiq = await callPool.bidLiquidity(args);

      // price == mean(lower, upper)
      // ask side liquidity == liquidity/2
      // bid side liquidity == liquidity/2

      expect(askLiq).to.eq(liq.div(2));
      expect(bidLiq).to.eq(liq.div(2));

      expect(await callPool.price(args, askLiq)).to.eq(_mean);
      expect(await callPool.price(args, bidLiq)).to.eq(_mean);
    });

    it('should revert if price is out of range', async () => {
      let args = {
        liquidityRate: parseEther('1'),
        marketPrice: parseEther('0.75'), // price == upper
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: true,
      };

      let liq = await callPool.liquidity(args);

      await expect(
        callPool.price(args, liq.mul(2)),
      ).to.be.revertedWithCustomError(
        callPool,
        'Pricing__PriceCannotBeComputedWithinTickRange',
      );

      args.isBuy = false;

      await expect(
        callPool.price(args, liq.mul(2)),
      ).to.be.revertedWithCustomError(
        callPool,
        'Pricing__PriceCannotBeComputedWithinTickRange',
      );
    });
  });

  describe('#nextPrice(Pricing.Args,uint256)', () => {
    it('should return upper tick for buy order if liquidity == 0', async () => {
      let args = {
        liquidityRate: 0,
        marketPrice: parseEther('0.5'),
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: true,
      };

      expect(await callPool.nextPrice(args, 0)).to.eq(args.upper);
    });

    it('should return lower tick for sell order if liquidity == 0', async () => {
      let args = {
        liquidityRate: 0,
        marketPrice: parseEther('0.5'),
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: false,
      };

      expect(await callPool.nextPrice(args, 0)).to.eq(args.lower);
    });

    it('should return the price when trade size == 0', async () => {
      let args = {
        liquidityRate: parseEther('1'),
        marketPrice: parseEther('0.5'),
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: true,
      };

      expect(await callPool.nextPrice(args, 0)).to.eq(args.marketPrice);

      args.isBuy = false;

      expect(await callPool.nextPrice(args, 0)).to.eq(args.marketPrice);
    });

    it('should return the next price for buy order when liquidity > 0 && trade size > 0', async () => {
      let args = {
        liquidityRate: parseEther('1'),
        marketPrice: parseEther('0.25'),
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: true,
      };

      let liq = await callPool.liquidity(args);
      let askLiq = await callPool.askLiquidity(args);
      let bidLiq = await callPool.bidLiquidity(args);

      // price == lower
      // ask side liquidity == liquidity
      // bid side liquidity == 0

      expect(askLiq).to.eq(liq);
      expect(bidLiq).to.eq(0);

      expect(await callPool.nextPrice(args, askLiq)).to.eq(args.upper);

      let _mean = mean(args.lower, args.upper); // parseEther('0.5')
      expect(await callPool.nextPrice(args, askLiq.div(2))).to.eq(_mean);

      _mean = mean(args.lower, _mean); // parseEther('0.375')
      expect(await callPool.nextPrice(args, askLiq.div(4))).to.eq(_mean);

      _mean = mean(args.lower, args.upper); // parseEther('0.5')
      args.marketPrice = _mean;

      liq = await callPool.liquidity(args);
      askLiq = await callPool.askLiquidity(args);
      bidLiq = await callPool.bidLiquidity(args);

      // price == mean(lower, upper)
      // ask side liquidity == liquidity/2
      // bid side liquidity == liquidity/2

      expect(askLiq).to.eq(liq.div(2));
      expect(bidLiq).to.eq(liq.div(2));

      expect(await callPool.nextPrice(args, askLiq)).to.eq(args.upper);
      expect(await callPool.nextPrice(args, bidLiq)).to.eq(args.upper);

      _mean = mean(args.marketPrice, args.upper); // parseEther('0.625')
      expect(await callPool.nextPrice(args, askLiq.div(2))).to.eq(_mean);
      expect(await callPool.nextPrice(args, bidLiq.div(2))).to.eq(_mean);

      _mean = mean(args.marketPrice, _mean); // parseEther('0.5625')
      expect(await callPool.nextPrice(args, askLiq.div(4))).to.eq(_mean);
      expect(await callPool.nextPrice(args, bidLiq.div(4))).to.eq(_mean);
    });

    it('should return the next price for sell order when liquidity > 0 && trade size > 0', async () => {
      let args = {
        liquidityRate: parseEther('1'),
        marketPrice: parseEther('0.75'),
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: false,
      };

      let liq = await callPool.liquidity(args);
      let askLiq = await callPool.askLiquidity(args);
      let bidLiq = await callPool.bidLiquidity(args);

      // price == upper
      // ask side liquidity == 0
      // bid side liquidity == liquidity

      expect(askLiq).to.eq(0);
      expect(bidLiq).to.eq(liq);

      expect(await callPool.nextPrice(args, bidLiq)).to.eq(args.lower);

      let _mean = mean(args.lower, args.upper); // parseEther('0.5')
      expect(await callPool.nextPrice(args, bidLiq.div(2))).to.eq(_mean);

      _mean = mean(_mean, args.upper); // parseEther('0.625')
      expect(await callPool.nextPrice(args, bidLiq.div(4))).to.eq(_mean);

      _mean = mean(args.lower, args.upper); // parseEther('0.5')
      args.marketPrice = _mean;

      liq = await callPool.liquidity(args);
      askLiq = await callPool.askLiquidity(args);
      bidLiq = await callPool.bidLiquidity(args);

      // price == mean(lower, upper)
      // ask side liquidity == liquidity/2
      // bid side liquidity == liquidity/2

      expect(askLiq).to.eq(liq.div(2));
      expect(bidLiq).to.eq(liq.div(2));

      expect(await callPool.nextPrice(args, askLiq)).to.eq(args.lower);
      expect(await callPool.nextPrice(args, bidLiq)).to.eq(args.lower);

      _mean = mean(args.lower, args.marketPrice); // parseEther('0.375')
      expect(await callPool.nextPrice(args, askLiq.div(2))).to.eq(_mean);
      expect(await callPool.nextPrice(args, bidLiq.div(2))).to.eq(_mean);

      _mean = mean(_mean, args.marketPrice); // parseEther('0.4375')
      expect(await callPool.nextPrice(args, askLiq.div(4))).to.eq(_mean);
      expect(await callPool.nextPrice(args, bidLiq.div(4))).to.eq(_mean);
    });

    it('should revert if price is out of range', async () => {
      let args = {
        liquidityRate: parseEther('1'),
        marketPrice: parseEther('0.75'), // price == upper
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: true,
      };

      let liq = await callPool.liquidity(args);

      await expect(
        callPool.nextPrice(args, liq.mul(2)),
      ).to.be.revertedWithCustomError(
        callPool,
        'Pricing__PriceCannotBeComputedWithinTickRange',
      );

      args.isBuy = false;

      await expect(
        callPool.nextPrice(args, liq.mul(2)),
      ).to.be.revertedWithCustomError(
        callPool,
        'Pricing__PriceCannotBeComputedWithinTickRange',
      );
    });
  });

  describe('#keyHash(Position.Key,uint256)', () => {
    it('should return key hash', async () => {
      const key = {
        owner: deployer.address,
        operator: deployer.address,
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        orderType: 0,
        isCall: isCall,
        strike: strike,
      };

      const keyHash = ethers.utils.keccak256(
        ethers.utils.defaultAbiCoder.encode(
          ['address', 'address', 'uint256', 'uint256', 'uint8'],
          [key.owner, key.operator, key.lower, key.upper, key.orderType],
        ),
      );

      expect(await callPool.keyHash(key)).to.eq(keyHash);
    });
  });

  describe('#opposite(Position.OrderType)', () => {
    it('should return opposite order type', async () => {
      expect(await callPool.opposite(0)).to.eq(5);
      expect(await callPool.opposite(5)).to.eq(0);
      expect(await callPool.opposite(1)).to.eq(3);
      expect(await callPool.opposite(3)).to.eq(1);
      expect(await callPool.opposite(2)).to.eq(4);
      expect(await callPool.opposite(4)).to.eq(2);
    });
  });

  describe('#isLeft(Position.OrderType)', () => {
    it('should return true if order type is bid side', async () => {
      expect(await callPool.isLeft(0)).to.be.true;
      expect(await callPool.isLeft(1)).to.be.true;
      expect(await callPool.isLeft(2)).to.be.true;
      expect(await callPool.isLeft(3)).to.be.false;
      expect(await callPool.isLeft(4)).to.be.false;
      expect(await callPool.isLeft(5)).to.be.false;
    });
  });

  describe('#isRight(Position.OrderType)', () => {
    it('should return true if order type is bid side', async () => {
      expect(await callPool.isRight(0)).to.be.false;
      expect(await callPool.isRight(1)).to.be.false;
      expect(await callPool.isRight(2)).to.be.false;
      expect(await callPool.isRight(3)).to.be.true;
      expect(await callPool.isRight(4)).to.be.true;
      expect(await callPool.isRight(5)).to.be.true;
    });
  });

  describe('#proportion(Position.Key,uint256)', () => {
    let key: any;

    before(async () => {
      key = {
        owner: deployer.address,
        operator: deployer.address,
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        orderType: 0,
        isCall: isCall,
        strike: strike,
      };
    });

    it('should return 0 if lower >= price', async () => {
      expect(
        await callPool[
          'proportion((address,address,uint256,uint256,uint8,bool,uint256),uint256)'
        ](key, key.lower),
      ).to.eq(0);
      expect(
        await callPool[
          'proportion((address,address,uint256,uint256,uint8,bool,uint256),uint256)'
        ](key, key.lower.sub(1)),
      ).to.eq(0);
    });

    it('should return the proportional amount if lower < price && price < upper', async () => {
      for (const t of [
        [parseEther('0.3'), parseEther('0.1')],
        [parseEther('0.5'), parseEther('0.5')],
        [parseEther('0.7'), parseEther('0.9')],
      ]) {
        expect(
          await callPool[
            'proportion((address,address,uint256,uint256,uint8,bool,uint256),uint256)'
          ](key, t[0]),
        ).to.eq(t[1]);
      }
    });

    it('should return WAD if price > upper', async () => {
      expect(
        await callPool[
          'proportion((address,address,uint256,uint256,uint8,bool,uint256),uint256)'
        ](key, key.upper),
      ).to.eq(WAD);

      expect(
        await callPool[
          'proportion((address,address,uint256,uint256,uint8,bool,uint256),uint256)'
        ](key, key.upper.add(1)),
      ).to.eq(WAD);
    });
  });

  describe('#pieceWiseLinear(Position.Key,uint256)', () => {
    let key: any;

    before(async () => {
      key = {
        owner: deployer.address,
        operator: deployer.address,
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        orderType: 0,
        isCall: isCall,
        strike: strike,
      };
    });

    it('should return 0 if lower >= price', async () => {
      expect(await callPool.pieceWiseLinear(key, key.lower)).to.eq(0);
      expect(await callPool.pieceWiseLinear(key, key.lower.sub(1))).to.eq(0);
    });

    it('should return the price if lower < price && price < upper', async () => {
      for (const t of [
        [parseEther('0.3'), parseEther('0.1')],
        [parseEther('0.5'), parseEther('0.5')],
        [parseEther('0.7'), parseEther('0.9')],
      ]) {
        expect(await callPool.pieceWiseLinear(key, t[0])).to.eq(t[1]);
      }
    });

    it('should return WAD if price > upper', async () => {
      expect(await callPool.pieceWiseLinear(key, key.upper)).to.eq(WAD);
      expect(await callPool.pieceWiseLinear(key, key.upper.add(1))).to.eq(WAD);
    });

    it('should revert if lower >= upper', async () => {
      key.lower = key.upper;

      await expect(
        callPool.pieceWiseLinear(key, 0),
      ).to.be.revertedWithCustomError(
        callPool,
        'Position__LowerGreaterOrEqualUpper',
      );

      key.lower = key.upper.add(1);

      await expect(
        callPool.pieceWiseLinear(key, 0),
      ).to.be.revertedWithCustomError(
        callPool,
        'Position__LowerGreaterOrEqualUpper',
      );
    });
  });

  describe('#pieceWiseQuadratic(Position.Key,uint256)', () => {
    let key: any;

    before(async () => {
      key = {
        owner: deployer.address,
        operator: deployer.address,
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        orderType: 0,
        isCall: isCall,
        strike: strike,
      };
    });

    it('should return 0 if lower >= price', async () => {
      expect(await callPool.pieceWiseQuadratic(key, key.lower)).to.eq(0);
      expect(await callPool.pieceWiseQuadratic(key, key.lower.sub(1))).to.eq(0);
    });

    it('should return the price if lower < price && price < upper', async () => {
      for (const t of [
        [parseEther('0.3'), parseEther('0.0275')],
        [parseEther('0.5'), parseEther('0.1875')],
        [parseEther('0.7'), parseEther('0.4275')],
      ]) {
        expect(await callPool.pieceWiseQuadratic(key, t[0])).to.eq(t[1]);
      }
    });

    it('should return average price if price > upper', async () => {
      expect(await callPool.pieceWiseQuadratic(key, key.upper)).to.eq(
        mean(key.lower, key.upper),
      );

      expect(await callPool.pieceWiseQuadratic(key, key.upper.add(1))).to.eq(
        mean(key.lower, key.upper),
      );
    });

    it('should revert if lower >= upper', async () => {
      key.lower = key.upper;

      await expect(
        callPool.pieceWiseQuadratic(key, 0),
      ).to.be.revertedWithCustomError(
        callPool,
        'Position__LowerGreaterOrEqualUpper',
      );

      key.lower = key.upper.add(1);

      await expect(
        callPool.pieceWiseQuadratic(key, 0),
      ).to.be.revertedWithCustomError(
        callPool,
        'Position__LowerGreaterOrEqualUpper',
      );
    });
  });
});

function mean(a: BigNumber, b: BigNumber): BigNumber {
  return a.add(b).div(2);
}
