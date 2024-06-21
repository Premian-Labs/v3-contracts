import fs from 'fs';
import { IERC20__factory, PremiaAirdrip__factory } from '../typechain';
import { ethers } from 'hardhat';
import { parseEther } from 'ethers/lib/utils';
import { initialize } from './utils';
import { BigNumber } from 'ethers';

async function main() {
  const [deployer] = await ethers.getSigners();
  const { deployment } = await initialize(deployer);

  const premia = IERC20__factory.connect(deployment.tokens['PREMIA'], deployer);
  const balance = await premia.balanceOf(deployer.address);
  const totalAllocation = parseEther('2000000');

  if (!balance.eq(totalAllocation))
    throw new Error('Deployer PREMIA balance is not 2_000_000e18');

  const premiaAirdrip = PremiaAirdrip__factory.connect(
    deployment.premiaAirdrip.PremiaAirdripProxy.address,
    deployer,
  );

  await premia.approve(premiaAirdrip.address, totalAllocation);

  const snapshot = JSON.parse(fs.readFileSync('cache/airdrip.json').toString());
  let users: { addr: string; influence: string }[] = [];

  for (const user in snapshot.total) {
    // filter out users with less than 1 influence
    if (BigNumber.from(snapshot.total[user]).lt(parseEther('1'))) continue;
    users.push({ addr: user, influence: snapshot.total[user] });
  }

  const usersSizeChunk = users.length / 4;

  const firstChunk = users.slice(0, usersSizeChunk);
  const secondChunk = users.slice(usersSizeChunk, usersSizeChunk * 2);
  const thirdChunk = users.slice(usersSizeChunk * 2, usersSizeChunk * 3);
  const fourthChunk = users.slice(usersSizeChunk * 3, users.length);

  await premiaAirdrip.initialize(firstChunk, false);
  await premiaAirdrip.initialize(secondChunk, false);
  await premiaAirdrip.initialize(thirdChunk, false);
  await premiaAirdrip.initialize(fourthChunk, true);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
