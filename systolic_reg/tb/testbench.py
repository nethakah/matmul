import cocotb, random, os
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from golden_model import matrixMultiplier, generateMatrix

N = int(os.environ.get("N", 4))

@cocotb.test()
async def testMatrixMultiplier(dut): # async so we can wait for clock edge to happen
    
    # clock start
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    # reset
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)

    for testRun in range(100):
        width = 8
        matA = generateMatrix(N, width)
        matB = generateMatrix(N, width)

        await streamMatrixIn(dut, matA)
        await streamMatrixIn(dut, matB)
        
        # read results as they stream out
        softwareResult = matrixMultiplier(matA, matB)
        hardwareResult = await readHardwareResult(dut, N)

        assert softwareResult == hardwareResult, f"Error on trial {testRun}. Hardware: {hardwareResult}, Software: {softwareResult}"


async def streamMatrixIn(dut, mat: list):
    rows = len(mat)
    cols = len(mat[0])

    for row in range(rows):
        for col in range(cols):
            dut.s_axis_tdata.value = mat[row][col]
            dut.s_axis_tvalid.value = 1
            dut.s_axis_tlast.value = (row==rows-1 and col==cols-1)

            cycles = 0
            while True:
                await RisingEdge(dut.clk)
                cycles += 1
                if cycles > 100:
                    raise Exception(f"Timeout waiting for s_axis_tready at row={row} col={col}")
                if dut.s_axis_tready.value:
                    break
            

            dut.s_axis_tvalid.value = 0
            dut.s_axis_tlast.value = 0


async def readHardwareResult(dut, n):
    flatResult = []

    cycles = 0
    while True:
        dut.m_axis_tready.value = 1 if random.random() < 0.5 else 0 # lets us test backpressure
        await RisingEdge(dut.clk)
        cycles += 1
        if cycles > 1000:
            raise Exception(f"Timeout waiting for m_axis_tvalid after {cycles} cycles")
        if dut.m_axis_tvalid.value and dut.m_axis_tready.value:
            flatResult.append(int(dut.m_axis_tdata.value))
            if dut.m_axis_tlast.value:
                break
    
    dut.m_axis_tready.value = 0
    return [ flatResult[r*n:(r+1)*n] for r in range(n)]

 