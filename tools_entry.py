#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
命令行入口垫片（供 pyproject.toml 的 console_scripts 调用）
==========================================================

把分散在 patch/ 下的校验器与生成器收敛成两条标准命令：
  - myenglish-validate  -> 句子数据 Schema + 策略一致性校验
  - myenglish-generate  -> 最小句子生成器（demo / golden / matrix）

设计说明（给产品/小程序背景的同学）：
  这就像小程序里的「页面入口文件」——根目录只放一个转发器，
  真正的逻辑在 patch/sentence/tools/ 与 patch/tools/ 里，
  这里只负责「接收命令 -> 转发给对应函数」。
"""

import sys


def run_validate():
    """执行 validate_sentence_data.py（句子知识库结构 + 策略一致性校验）。"""
    # 动态加载工具脚本，复用其 main()，不重复造轮子
    sys.path.insert(0, "patch/sentence/tools")
    import validate_sentence_data
    validate_sentence_data.main()


def run_generate():
    """执行 mini_generator.py（最小句子生成器原型）。"""
    sys.path.insert(0, "patch/sentence/tools")
    import mini_generator
    mini_generator.main()


if __name__ == "__main__":
    # 直接 `python tools_entry.py` 默认跑校验
    run_validate()
