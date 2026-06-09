import paddle

print(f"CUDA available       : {paddle.device.is_compiled_with_cuda()}")
print(f"GPU count            : {paddle.device.cuda.device_count()}")

if paddle.device.is_compiled_with_cuda():
    paddle.device.set_device("gpu")
    x = paddle.ones([3, 3])
    y = paddle.ones([3, 3])
    z = paddle.matmul(x, y)
    print(f"GPU tensor test      : PASSED (result sum={z.numpy().sum()})")
    import paddle.version as pv
    print(f"CUDA version         : {pv.cuda()}")
    print(f"cuDNN version        : {pv.cudnn()}")
else:
    print("GPU tensor test      : SKIPPED (no CUDA)")