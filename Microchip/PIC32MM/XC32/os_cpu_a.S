/*
*********************************************************************************************************
*                                              uC/OS-III
*                                        The Real-Time Kernel
*
*                    Copyright 2009-2020 Silicon Laboratories Inc. www.silabs.com
*
*                    Copyright 2020 Oleg Nykytenko, oleg.nykytenko@gmail.com
*
*                                 SPDX-License-Identifier: APACHE-2.0
*
*               This software is subject to an open source license and is distributed by
*                Silicon Laboratories Inc. pursuant to the terms of the Apache License,
*                    Version 2.0 available at www.apache.org/licenses/LICENSE-2.0.
*
*********************************************************************************************************
*/

/*
*********************************************************************************************************
*
*                                               PIC32MM
*
*                                                 XC32
*
* File    : os_cpu_a.S
* Version : V3.08.00
*********************************************************************************************************
*/

#include "os_cpu_a.inc"
    
    
    .section .text,code
    .set noreorder
    .set nomips16
    .set noat


/*
*********************************************************************************************************
*                                          PUBLIC FUNCTIONS
*********************************************************************************************************
*/

    .global  OSStartHighRdy
    .global  OSIntCtxSw
    .global  OSCtxSw
    .global  CoreTimerIntHandler
    .global  _general_exception_context


/*
*********************************************************************************************************
*                                           OSStartHighRdy()
*
* Description: Starts the highest priority task that is available to run.  OSStartHighRdy() MUST:
*
*              a) Call OSTaskSwHook()
*              b) Set OSRunning to TRUE
*              c) Switch to the highest priority task.
*
*              The stack frame of the task to resume is assumed to look as follows:
*
*              OSTCBHighRdy->OSTCBStkPtr + 0x00    Free Entry                    (LOW Memory)
*                                        + 0x04    Status Register
*                                        + 0x08    EPC
*                                        + 0x0C    Special Purpose LO Register
*                                        + 0x10    Special Purpose HI Register
*                                        + 0x14    GPR[1]
*                                        + 0x18    GPR[2]
*                                        + 0x1C    GPR[3]
*                                        + 0x20    GPR[4]
*                                               |
*                                               |
*                                              \ /
*                                               V
*                                        + 0x80    GPR[28]
*                                        + 0x84    GPR[30]
*                                        + 0x88    GPR[31]                       (HIGH Memory)
*
* Note(s): 1) OSTaskStkInit(), which is responsible for initializing each task's stack, sets bit 0 of the
*             entry corresponding to the Status register.  Thus, interrupts will be enabled when each
*             task first runs.
*********************************************************************************************************
*/

    .ent OSStartHighRdy
OSStartHighRdy:

    la    $8,  OSTaskSwHook                    /* Call OSTaskSwHook()                                  */
    jalr  $8
    nop

    la    $8,  OSTCBHighRdyPtr                 /* Update the current TCB                               */
    lw    $9,  0($8)
    lw    $29, 0($9)                           /* Load the new task's stack pointer                    */

    OS_CPU_REGS_RESTORE
    
    eret

    .end OSStartHighRdy


/*
*********************************************************************************************************
*                                             OSIntCtxSw()
*
* Description: This function is used to perform a context switch following an ISR.
*
*              OSIntCtxSw() implements the following pseudo-code:
*
*                  OSTaskSwHook();
*                  OSPrioCur = OSPrioHighRdy;
*                  OSTCBCur  = OSTCBHighRdy;
*                  SP        = OSTCBHighRdy->OSTCBStkPtr;
*                  Restore the Status register and the EPC to their prior states;
*                  Restore the LO and HI registers;
*                  Restore each of the general purpose registers;
*                  Adjust the stack pointer;
*                  Execute an eret instruction to begin executing the new task;
*
*              Upon entry, the registers of the task being suspended have already been saved onto that
*              task's stack and the SP for the task has been saved in its OS_TCB by the ISR.
*
*              The stack frame of the task to resume is assumed to look as follows:
*
*              OSTCBHighRdy->OSTCBStkPtr + 0x00    Free Entry                    (LOW Memory)
*                                        + 0x04    Status Register
*                                        + 0x08    EPC
*                                        + 0x0C    Special Purpose LO Register
*                                        + 0x10    Special Purpose HI Register
*                                        + 0x14    GPR[1]
*                                        + 0x18    GPR[2]
*                                        + 0x1C    GPR[3]
*                                        + 0x20    GPR[4]
*                                               |
*                                               |
*                                              \ /
*                                               V
*                                        + 0x80    GPR[28]
*                                        + 0x84    GPR[30]
*                                        + 0x88    GPR[31]                       (HIGH Memory)
*********************************************************************************************************
*/

    .ent OSIntCtxSw
OSIntCtxSw:

    la    $8,  OSTaskSwHook                    /* Call OSTaskSwHook()                                  */
    jalr  $8
    nop

    la    $8,  OSPrioHighRdy                   /* Update the current priority                          */
    lbu   $9,  0($8)
    la    $10, OSPrioCur
    sb    $9,  0($10)

    la    $8,  OSTCBHighRdyPtr                 /* Update the current TCB                               */
    lw    $9,  0($8)
    la    $10, OSTCBCurPtr
    sw    $9,  0($10)

    lw    $29, 0($9)                           /* Load the new task's stack pointer                    */

    OS_CPU_REGS_RESTORE

    eret                                       /* Resume execution in new task                         */

    .end OSIntCtxSw


/*
*********************************************************************************************************
*                                               OSCtxSw
*
* Description: Performs a Context switch from a task.  This function is ALWAYS called with interrupts
*              DISABLED.
*
*              OSCtxSw() implements the following pseudo-code:
*
*                  Adjust the stack pointer;
*                  Save each of the general purpose registers;
*                  Save the LO and HI registers;
*                  Save the EPC and the Status register;
*                  Verify that a syscall exception (corresponding to OS_TASK_SW) occurred;
*                  OSTCBCur->OSTCBStkPtr = SP;
*                  OSTaskSwHook();
*                  OSPrioCur = OSPrioHighRdy;
*                  OSTCBCur  = OSTCBHighRdy;
*                  SP        = OSTCBHighRdy->OSTCBStkPtr;
*                  Restore the Status register and the EPC to their prior states;
*                  Restore the LO and HI registers;
*                  Restore each of the general purpose registers;
*                  Adjust the stack pointer;
*                  Execute an eret instruction to begin executing the new task;
*
*              The stack frame of the task to suspend will look as follows when OSCtxSw() is done:
*
*              OSTCBHighRdy->OSTCBStkPtr + 0x00    Free Entry                    (LOW Memory)
*                                        + 0x04    Status Register
*                                        + 0x08    EPC
*                                        + 0x0C    Special Purpose LO Register
*                                        + 0x10    Special Purpose HI Register
*                                        + 0x14    GPR[1]
*                                        + 0x18    GPR[2]
*                                        + 0x1C    GPR[3]
*                                        + 0x20    GPR[4]
*                                               |
*                                               |
*                                              \ /
*                                               V
*                                        + 0x80    GPR[28]
*                                        + 0x84    GPR[30]
*                                        + 0x88    GPR[31]                       (HIGH Memory)
*
*              The stack frame of the task to resume looks as follows:
*
*              OSTCBHighRdy->OSTCBStkPtr + 0x00    Free Entry                    (LOW Memory)
*                                        + 0x04    Status Register
*                                        + 0x08    EPC
*                                        + 0x0C    Special Purpose LO Register
*                                        + 0x10    Special Purpose HI Register
*                                        + 0x14    GPR[1]
*                                        + 0x18    GPR[2]
*                                        + 0x1C    GPR[3]
*                                        + 0x20    GPR[4]
*                                               |
*                                               |
*                                              \ /
*                                               V
*                                        + 0x80    GPR[28]
*                                        + 0x84    GPR[30]
*                                        + 0x88    GPR[31]                       (HIGH Memory)
*********************************************************************************************************
*/

    .ent OSCtxSw
OSCtxSw:
    la    $8,  OSTCBCurPtr                     /* Save the current task's stack pointer                */
    lw    $9,  0($8)
    sw    $29, 0($9)

    la    $8,  OSTaskSwHook                    /* Call OSTaskSwHook()                                  */
    jalr  $8
    nop

    la    $8,  OSPrioHighRdy                   /* Update the current priority                          */
    lbu   $9,  0($8)
    la    $10, OSPrioCur
    sb    $9,  0($10)

    la    $8,  OSTCBHighRdyPtr                 /* Update the current TCB                               */
    lw    $9,  0($8)
    la    $10, OSTCBCurPtr
    sw    $9,  0($10)

    lw    $29, 0($9)                           /* Load the new task's stack pointer                    */

    OS_CPU_REGS_RESTORE

    eret                                       /* Resume execution in new task                         */

    .end OSCtxSw


/*
*********************************************************************************************************
*                                          CoreTimerIntHandler
*
* Description: The core timer, which is implemented by the Coprocessor 0 Count and Compare registers,
*              is the source of uC/OS-III's tick interrupts.  This function handles those interrupts,
*              saving the current task's context and then calling OSTimeTick(), uC/OS-III's CPU-
*              independent routine for processing tick interrupts.
*
*              The interrupted task's context is saved onto its stack as follows:
*
*
*              OSTCBHighRdy->OSTCBStkPtr + 0x00    Free Entry                    (LOW Memory)
*                                        + 0x04    Status Register
*                                        + 0x08    EPC
*                                        + 0x0C    Special Purpose LO Register
*                                        + 0x10    Special Purpose HI Register
*                                        + 0x14    GPR[1]
*                                        + 0x18    GPR[2]
*                                        + 0x1C    GPR[3]
*                                        + 0x20    GPR[4]
*                                               |
*                                               |
*                                              \ /
*                                               V
*                                        + 0x80    GPR[28]
*                                        + 0x84    GPR[30]
*                                        + 0x88    GPR[31]                       (HIGH Memory)
*********************************************************************************************************
*/

    .ent CoreTimerIntHandler
CoreTimerIntHandler:

    OS_CPU_REGS_SAVE	NOT_EXCEPTION_CAUSE

    la    $8,  OSIntNestingCtr                 /* See if OSIntNesting == 0                             */
    lbu   $9,  0($8)
    bne   $0,  $9, TICK_INC_NESTING
    nop

    la    $10, OSTCBCurPtr                     /* Save the current task's stack pointer                */
    lw    $11, 0($10)
    sw    $29, 0($11)

TICK_INC_NESTING:
    la    $8,  OSIntEnter		       /* Call OSIntEnter() for ENTER ISR OS Notification      */
    jalr  $8
    nop

    mfc0  $8, $12, 0                           /* Update the Status register's IPL bits                */
    mfc0  $9, $13, 0
    andi  $9, $9,  0xFC00
    ins   $8, $0,  10, 6
    or    $8, $8,  $9
    mtc0  $8, $12, 0
    ehb

    la    $8,  BSP_TickISR_Handler             /* Call BSP_TickISR_Handler() to handle the interrupt   */
    jalr  $8
    nop

    la    $8,  OSTimeTick                      /* Call OSTimeTick()                                    */
    jalr  $8
    nop

    la    $8,  OSIntExit                       /* Call OSIntExit()                                     */
    jalr  $8
    nop

    OS_CPU_REGS_RESTORE

    eret

    .end CoreTimerIntHandler

    
    
    
/*
*********************************************************************************************************
*                                      _general_exception_handler()
*
* Description: general exception handler.
*
*********************************************************************************************************
*/    
    .ent _general_exception_context
_general_exception_context:
    OS_CPU_REGS_SAVE	EXCEPTION_CAUSE

    ori   $8,  $0,  0x007C                     /* Switch context only if a syscall exception occurred  */
    mfc0  $9,  $13, 0
    and   $9,  $9,  $8
    ori   $10, $0,  0x0020
    beq   $9,  $10, OS_CTX_SW
    nop

    la    $8,  BSP_Except_Handler             /* Call BSP_Except_Handler() for exceptions not...       */
    jalr  $8                                  /* ...triggered by syscall.                              */
    nop

    b     RESTORE_CTX
    nop

OS_CTX_SW:
    la    $8,  OSCtxSw			      /* Switch context					       */
    jalr  $8
    nop

RESTORE_CTX:
    OS_CPU_REGS_RESTORE

    eret                                       /* Resume execution in new task			       */
    .end _general_exception_context
