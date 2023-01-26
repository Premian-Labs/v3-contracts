import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { PositionMock, PositionMock__factory } from '../../typechain';
import { parseEther } from 'ethers/lib/utils';
import { average } from '../../utils/math';

describe('Position', () => {
  let deployer: SignerWithAddress;
  let instance: PositionMock;

  let strike = 1000;
  let isCall: boolean;

  let WAD = parseEther('1');

  enum OrderType {
    CSUP,
    CS,
    LC,
  }

  before(async function () {
    [deployer] = await ethers.getSigners();
    instance = await new PositionMock__factory(deployer).deploy();

    for (isCall of [true, false]) {
    }
  });

  describe('#keyHash', () => {
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

      expect(await instance.keyHash(key)).to.eq(keyHash);
    });
  });

  describe('#isShort', () => {
    it('should return true if orderType is short', async () => {
      expect(await instance.isShort(OrderType.CS)).is.true;
      expect(await instance.isShort(OrderType.CSUP)).is.true;
    });

    it('should return false if orderType is not short', async () => {
      expect(await instance.isShort(OrderType.LC)).is.false;
    });
  });

  describe('#pieceWiseLinear', () => {
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
      expect(await instance.pieceWiseLinear(key, key.lower)).to.eq(0);
      expect(await instance.pieceWiseLinear(key, key.lower.sub(1))).to.eq(0);
    });

    it('should return the price if lower < price && price < upper', async () => {
      for (const t of [
        [parseEther('0.3'), parseEther('0.1')],
        [parseEther('0.5'), parseEther('0.5')],
        [parseEther('0.7'), parseEther('0.9')],
      ]) {
        expect(await instance.pieceWiseLinear(key, t[0])).to.eq(t[1]);
      }
    });

    it('should return WAD if price > upper', async () => {
      expect(await instance.pieceWiseLinear(key, key.upper)).to.eq(WAD);
      expect(await instance.pieceWiseLinear(key, key.upper.add(1))).to.eq(WAD);
    });

    it('should revert if lower >= upper', async () => {
      key.lower = key.upper;

      await expect(
        instance.pieceWiseLinear(key, 0),
      ).to.be.revertedWithCustomError(
        instance,
        'Position__LowerGreaterOrEqualUpper',
      );

      key.lower = key.upper.add(1);

      await expect(
        instance.pieceWiseLinear(key, 0),
      ).to.be.revertedWithCustomError(
        instance,
        'Position__LowerGreaterOrEqualUpper',
      );
    });
  });

  describe('#pieceWiseQuadratic', () => {
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
      expect(await instance.pieceWiseQuadratic(key, key.lower)).to.eq(0);
      expect(await instance.pieceWiseQuadratic(key, key.lower.sub(1))).to.eq(0);
    });

    it('should return the price if lower < price && price < upper', async () => {
      for (const t of [
        [parseEther('0.3'), parseEther('0.0275')],
        [parseEther('0.5'), parseEther('0.1875')],
        [parseEther('0.7'), parseEther('0.4275')],
      ]) {
        expect(await instance.pieceWiseQuadratic(key, t[0])).to.eq(t[1]);
      }
    });

    it('should return average price if price > upper', async () => {
      expect(await instance.pieceWiseQuadratic(key, key.upper)).to.eq(
        average(key.lower, key.upper),
      );

      expect(await instance.pieceWiseQuadratic(key, key.upper.add(1))).to.eq(
        average(key.lower, key.upper),
      );
    });

    it('should revert if lower >= upper', async () => {
      key.lower = key.upper;

      await expect(
        instance.pieceWiseQuadratic(key, 0),
      ).to.be.revertedWithCustomError(
        instance,
        'Position__LowerGreaterOrEqualUpper',
      );

      key.lower = key.upper.add(1);

      await expect(
        instance.pieceWiseQuadratic(key, 0),
      ).to.be.revertedWithCustomError(
        instance,
        'Position__LowerGreaterOrEqualUpper',
      );
    });
  });
});
