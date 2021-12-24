let instance = await Factory.deployed();
let r = await instance.newPool();
let poolAddress = r.logs[0].args["1"];
let p = await Pool.at(poolAddress);
p.isFinalized();
p.bind(
  "0xFa00a8361D8160CbE8fe095FA4069C5cf0Fbd534",
  web3.utils.toWei("100000"),
  web3.utils.toWei("10")
);
