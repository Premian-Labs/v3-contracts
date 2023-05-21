import {
  ERC20Mock__factory,
  VxPremia,
  VxPremia__factory,
  VxPremiaProxy__factory,
} from '../../typechain';
import { getEventArgs } from '../../utils/events';
import { increase, ONE_DAY } from '../../utils/time';
import { deployMockContract } from '@ethereum-waffle/mock-contract';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { parseEther, solidityPack } from 'ethers/lib/utils';
import { ethers } from 'hardhat';

/* Example to decode packed target data

const targetData = '0x000000000000000000000000000000000000000101;
const pool = hexDataSlice(
  targetData,
  0,
  20,
);
const isCallPool = hexDataSlice(
  targetData,
  20,
  21,
);

 */

////////////////////

const poolAddresses = [
  '0x000004354F938CF1aCC2414B68951ad7a8730fB6',
  '0x100004354F938CF1aCC2414B68951ad7a8730fB6',
  '0x200004354F938CF1aCC2414B68951ad7a8730fB6',
];

describe('VxPremia', () => {
  async function deploy() {
    const [deployer, alice, bob] = await ethers.getSigners();

    const premia = await new ERC20Mock__factory(deployer).deploy('PREMIA', 18);
    const usdc = await new ERC20Mock__factory(deployer).deploy('USDC', 6);

    const premiaDiamond = await deployMockContract(deployer as any, [
      'function getPoolList() external view returns (uint256[])',
    ]);

    await premiaDiamond.mock.getPoolList.returns(poolAddresses);

    const vxPremiaImpl = await new VxPremia__factory(deployer).deploy(
      premiaDiamond.address,
      ethers.constants.AddressZero,
      premia.address,
      usdc.address,
      ethers.constants.AddressZero,
    );

    const vxPremiaProxy = await new VxPremiaProxy__factory(deployer).deploy(
      vxPremiaImpl.address,
    );

    const vxPremia = VxPremia__factory.connect(vxPremiaProxy.address, deployer);

    for (const u of [alice, bob]) {
      await premia.mint(u.address, parseEther('100'));
      await premia
        .connect(u)
        .approve(vxPremia.address, ethers.constants.MaxUint256);
    }

    return { deployer, alice, bob, premia, usdc, vxPremia, poolAddresses };
  }

  it('should reset user votes', async () => {
    const { vxPremia, alice, deployer } = await loadFixture(deploy);

    await vxPremia.connect(alice).stake(parseEther('10'), ONE_DAY * 365);

    const target1 = solidityPack(['address', 'bool'], [poolAddresses[0], true]);

    const target2 = solidityPack(['address', 'bool'], [poolAddresses[1], true]);

    await vxPremia.connect(alice).castVotes([
      {
        amount: parseEther('7'),
        version: 0,
        target: target1,
      },
      {
        amount: parseEther('3'),
        version: 0,
        target: target2,
      },
    ]);

    await vxPremia.connect(alice).castVotes([
      {
        amount: parseEther('7'),
        version: 0,
        target: target1,
      },
      {
        amount: parseEther('3'),
        version: 0,
        target: target2,
      },
    ]);

    let votes = await vxPremia.getUserVotes(alice.address);

    expect(votes.length).to.eq(2);

    expect(votes[0].target).to.eq(target1);
    expect(votes[0].amount).to.eq(parseEther('7'));

    expect(votes[1].target).to.eq(target2);
    expect(votes[1].amount).to.eq(parseEther('3'));

    await vxPremia.connect(deployer).resetUserVotes(alice.address);

    votes = await vxPremia.getUserVotes(alice.address);
    expect(votes.length).to.eq(0);
  });

  it('should fail resetting user votes if not called from owner', async () => {
    const { vxPremia, alice } = await loadFixture(deploy);

    await expect(
      vxPremia.connect(alice).resetUserVotes(alice.address),
    ).to.be.revertedWithCustomError(vxPremia, 'Ownable__NotOwner');
  });
});
