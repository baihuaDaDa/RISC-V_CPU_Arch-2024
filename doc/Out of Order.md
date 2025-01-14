Out of Order
===
> 测试点：`001_array_test2`

测试点汇编码：
```
 116:	89e2                	mv	s3,s8
 118:	010c0a13          	addi	s4,s8,16
 11c:	8be2                	mv	s7,s8
 11e:	00f10933          	add	s2,sp,a5
 122:	4aa5                	li	s5,9
 124:	000ba403          	lw	s0,0(s7)
 128:	4d01                	li	s10,0
 12a:	0e044763          	bltz	s0,218 <main+0x14c>
 12e:	4d81                	li	s11,0
 130:	45a9                	li	a1,10
 132:	8522                	mv	a0,s0
 134:	37a5                	jal	9c <__modsi3>
```

![](https://notes.sjtu.edu.cn/uploads/upload_60ca3e2fa4147c36a8cb944cef4b4121.png)

波形图中可以看到位于 RoB `02` 位置的指令 `128: li s10,0` 先完成了运算，由 ALU 将结果 `00000000` 写回 RoB 并将状态修改为 `WRITE_RESULT`。而在下一个周期 Memory 才将位于 RoB `01` 位置的指令 `124: lw s0,0(s7)` 写回 RoB。程序里靠前的 `124` 指令比靠后的 `128` 指令后执行完成并得到结果，说明 CPU 存在乱序执行。