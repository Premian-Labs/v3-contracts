import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { OptionMathMock, OptionMathMock__factory } from '../../typechain';
import { parseEther } from 'ethers/lib/utils';

describe('OptionMath', () => {
  let deployer: SignerWithAddress;
  let instance: OptionMathMock;

  before(async function () {
    [deployer] = await ethers.getSigners();
    instance = await new OptionMathMock__factory(deployer).deploy();
  });

  describe('beta = 0.25', () => {
    let beta = parseEther('0.25');

    it('', async () => {
      await testStrikeIntervalRange(parseEther('0.0025'), beta);
    });

    // it('should return 0.0025 for 1', async () => {
    //   let interval = BigNumber.from('2500000000000000');
    //   let x = BigNumber.from('1000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 0.025 for 3', async () => {
    //   let interval = BigNumber.from('25000000000000000');
    //   let x = BigNumber.from('3000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 0.025 for 4', async () => {
    //   let interval = BigNumber.from('25000000000000000');
    //   let x = BigNumber.from('4000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 0.025 for 5', async () => {
    //   let interval = BigNumber.from('25000000000000000');
    //   let x = BigNumber.from('5000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 0.025 for 9', async () => {
    //   let interval = BigNumber.from('25000000000000000');
    //   let x = BigNumber.from('9000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 0.025 for 10', async () => {
    //   let interval = BigNumber.from('25000000000000000');
    //   let x = BigNumber.from('10000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 0.25 for 11', async () => {
    //   let interval = BigNumber.from('250000000000000000');
    //   let x = BigNumber.from('11000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 0.25 for 36', async () => {
    //   let interval = BigNumber.from('250000000000000000');
    //   let x = BigNumber.from('36000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 0.25 for 87', async () => {
    //   let interval = BigNumber.from('250000000000000000');
    //   let x = BigNumber.from('87000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 0.25 for 999', async () => {
    //   let interval = BigNumber.from('250000000000000000');
    //   let x = BigNumber.from('99900000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 0.25 for 100', async () => {
    //   let interval = BigNumber.from('250000000000000000');
    //   let x = BigNumber.from('100000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 2.5 for 101', async () => {
    //   let interval = BigNumber.from('2500000000000000000');
    //   let x = BigNumber.from('101000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 2.5 for 117', async () => {
    //   let interval = BigNumber.from('2500000000000000000');
    //   let x = BigNumber.from('117000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 2.5 for 153', async () => {
    //   let interval = BigNumber.from('2500000000000000000');
    //   let x = BigNumber.from('153000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 2.5 for 199', async () => {
    //   let interval = BigNumber.from('2500000000000000000');
    //   let x = BigNumber.from('199000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 2.5 for 667', async () => {
    //   let interval = BigNumber.from('2500000000000000000');
    //   let x = BigNumber.from('667000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 2.5 for 709', async () => {
    //   let interval = BigNumber.from('2500000000000000000');
    //   let x = BigNumber.from('709000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 2.5 for 816', async () => {
    //   let interval = BigNumber.from('2500000000000000000');
    //   let x = BigNumber.from('816000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 2.5 for 999', async () => {
    //   let interval = BigNumber.from('2500000000000000000');
    //   let x = BigNumber.from('1000000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 2.5 for 1000', async () => {
    //   let interval = BigNumber.from('2500000000000000000');
    //   let x = BigNumber.from('1000000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 25 for 1001', async () => {
    //   let interval = BigNumber.from('25000000000000000000');
    //   let x = BigNumber.from('1001000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 25 for 5298', async () => {
    //   let interval = BigNumber.from('25000000000000000000');
    //   let x = BigNumber.from('5298000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 25 for 9999', async () => {
    //   let interval = BigNumber.from('25000000000000000000');
    //   let x = BigNumber.from('9999000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 25 for 10000', async () => {
    //   let interval = BigNumber.from('25000000000000000000');
    //   let x = BigNumber.from('10000000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 250 for 10001', async () => {
    //   let interval = BigNumber.from('250000000000000000000');
    //   let x = BigNumber.from('10001000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 250 for 15336', async () => {
    //   let interval = BigNumber.from('250000000000000000000');
    //   let x = BigNumber.from('15336000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 250 for 15802', async () => {
    //   let interval = BigNumber.from('250000000000000000000');
    //   let x = BigNumber.from('15802000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 250 for 22508', async () => {
    //   let interval = BigNumber.from('250000000000000000000');
    //   let x = BigNumber.from('22508000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 250 for 32693', async () => {
    //   let interval = BigNumber.from('250000000000000000000');
    //   let x = BigNumber.from('32693000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 250 for 38858', async () => {
    //   let interval = BigNumber.from('250000000000000000000');
    //   let x = BigNumber.from('38858000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 250 for 43442', async () => {
    //   let interval = BigNumber.from('250000000000000000000');
    //   let x = BigNumber.from('43442000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });

    // it('should return 250 for 48183', async () => {
    //   let interval = BigNumber.from('250000000000000000000');
    //   let x = BigNumber.from('48183000000000000000000');
    //   let y = await instance.strikeInterval(beta, x);
    //   console.log(`x: ${x}, y: ${y}`);
    //   expect(y).to.eq(interval);
    // });
  });

  describe('beta = 0.5', async () => {
    let beta = parseEther('0.5');

    it('', async () => {
      await testStrikeIntervalRange(parseEther('0.005'), beta);
    });
  });

  describe('beta = 0.75', async () => {
    let beta = parseEther('0.75');

    it('', async () => {
      await testStrikeIntervalRange(parseEther('0.0075'), beta);
    });
  });

  describe('beta = 1.0', async () => {
    let beta = parseEther('1');

    it('', async () => {
      await testStrikeIntervalRange(parseEther('0.01'), beta);
    });
  });

  async function testStrikeIntervalRange(interval: BigNumber, beta: BigNumber) {
    let x = parseEther('1');
    let limit = parseEther('10000');

    let counter = 0;
    let ruler = 1;

    while (x.lte(limit)) {
      let y = await instance.strikeInterval(beta, x);
      x = x.add(parseEther('1'));

      expect(y).to.eq(interval);

      counter++;

      if (counter % ruler == 0) {
        // increase interval proportionally with counter
        // e.g.
        //      counter  -> 1       -> 10
        //      interval -> 0.01ETH -> 0.1ETH
        interval = interval.mul(10);
        ruler = ruler * 10;
      }
    }
  }
});
