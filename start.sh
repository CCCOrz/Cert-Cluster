#!/bin/bash
sleep 1

main() {
    echo ""
    echo -e "1.111"
    echo ""
    echo -e "任意键退出"
    echo ""
    read -rp "请选择以下序号: " ChooseIndex
    case "$ChooseIndex" in
        1) echo -e "111" ;;
        *) exit 1 ;;
    esac
}

main
