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
import { revertToSnapshotAfterEach } from '../../utils/time';

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

  let strike = parseEther('1000'); // ATM
  let maturity = 1645776000; // Fri Feb 25 2022 08:00:00 GMT+0000

  let isCall: boolean;
  let collateral: BigNumber;

  before(async () => {
    [deployer, lp] = await ethers.getSigners();

    underlying = await new ERC20Mock__factory(deployer).deploy('WETH', 18);
    base = await new ERC20Mock__factory(deployer).deploy('USDC', 6);

    p = await PoolUtil.deploy(deployer, underlying.address, true, true);

    await underlying.mint(lp.address, parseEther('1000000'));
    await base.mint(lp.address, parseEther('1000'));

    baseOracle = await deployMockContract(deployer as any, [
      'function latestAnswer() external view returns (int256)',
      'function decimals () external view returns (uint8)',
    ]);

    await baseOracle.mock.latestAnswer.returns(100000000);
    await baseOracle.mock.decimals.returns(8);

    underlyingOracle = await deployMockContract(deployer as any, [
      'function latestAnswer() external view returns (int256)',
      'function decimals () external view returns (uint8)',
    ]);

    await underlyingOracle.mock.latestAnswer.returns(100000000000);
    await underlyingOracle.mock.decimals.returns(8);

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

  describe('__internal', function () {
    describe('#_getPricing', () => {
      it('should return pool state', async () => {
        let isBuy = true;
        let args = await callPool._getPricing(isBuy);

        expect(args.liquidityRate).to.eq(0);
        expect(args.marketPrice).to.eq(0);
        expect(args.lower).to.eq(parseEther('0.001'));
        expect(args.upper).to.eq(parseEther('1'));
        expect(args.isBuy).to.eq(isBuy);

        args = await callPool._getPricing(!isBuy);

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
          orderType: 2,
          isCall: isCall,
          strike: strike,
        };

        await underlying.connect(lp).approve(callPool.address, collateral);

        const nearestBelow = await callPool.getNearestTicksBelow(lower, upper);

        await callPool
          .connect(lp)
          [
            'deposit((address,address,uint256,uint256,uint8,bool,uint256),uint256,uint256,uint256,uint256)'
          ](
            position,
            nearestBelow.nearestBelowLower,
            nearestBelow.nearestBelowUpper,
            parseEther('2000'),
            0,
          );

        args = await callPool._getPricing(isBuy);

        expect(args.liquidityRate).to.eq(parseEther('4'));
        expect(args.marketPrice).to.eq(upper);
        expect(args.lower).to.eq(lower);
        expect(args.upper).to.eq(upper);
        expect(args.isBuy).to.eq(isBuy);

        args = await callPool._getPricing(!isBuy);

        expect(args.liquidityRate).to.eq(parseEther('4'));
        expect(args.marketPrice).to.eq(upper);
        expect(args.lower).to.eq(lower);
        expect(args.upper).to.eq(upper);
        expect(args.isBuy).to.eq(!isBuy);
      });
    });
  });

  describe('#formatTokenId', () => {
    it('should properly format token id', async () => {
      const operator = '0x1000000000000000000000000000000000000001';
      const tokenId = await callPool.formatTokenId(
        operator,
        parseEther('0.001'),
        parseEther('1'),
        2,
      );

      console.log(tokenId.toHexString());

      expect(tokenId.mask(10)).to.eq(1);
      expect(tokenId.shr(10).mask(10)).to.eq(1000);
      expect(tokenId.shr(20).mask(160)).to.eq(operator);
      expect(tokenId.shr(180).mask(4)).to.eq(2);
      expect(tokenId.shr(252).mask(4)).to.eq(1);
    });
  });

  describe('#parseTokenId', () => {
    it('should properly parse token id', async () => {
      const r = await callPool.parseTokenId(
        BigNumber.from(
          '0x10000000000000000021000000000000000000000000000000000000001fa001',
        ),
      );

      expect(r.lower).to.eq(parseEther('0.001'));
      expect(r.upper).to.eq(parseEther('1'));
      expect(r.operator).to.eq('0x1000000000000000000000000000000000000001');
      expect(r.orderType).to.eq(2);
      expect(r.version).to.eq(1);
    });
  });
});
