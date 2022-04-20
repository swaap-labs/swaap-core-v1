const { createTypeData, signTypedData } = require('./eip712');
// MultiSig(address _user,uint256 _withdrawId,address _token, uint256 _amount)
const name = 'Swaap Pool';
const version = '1.0.0';
const primaryType = '_joinPool';
const Types = {
  [primaryType]: [
      { name: "owner", type: "address" },
      { name: "poolAmountOut", type: "uint256" },
      { name: "maxAmountsIn", type: "uint256[]" },
      { name: "deadline", type: "uint256" },
      { name: "nonce", type: "uint256"},
  ],
};

async function sign(owner, poolAmountOut, maxAmountsIn, deadline, nonce, verifyingContract) {
  const chainId = Number(await web3.eth.getChainId());
  const data = createTypeData(
    { name: name, version: version, chainId: chainId, verifyingContract: verifyingContract },
    primaryType,
    { owner, poolAmountOut, maxAmountsIn, deadline, nonce },
    Types
  );
  return (await signTypedData(web3, owner, data)).sig;
}

module.exports = { sign };