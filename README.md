# NoOpHookFee

NoOpHookFee is uniswap Hook Fee implementation for Uniswap V4. This collects extra fees on swap operations by intercepting swap calls through hooks. Specifically, it differentiates between exact input and exact output swaps, applying a fixed fee on the input token for each operation.