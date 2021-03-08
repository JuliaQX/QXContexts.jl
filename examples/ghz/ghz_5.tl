# version: 0.1.0
outputs 5
load t636 data_1
load t637 data_2
load t638 data_2
load t639 data_2
load t640 data_2
load t641 data_3
load t642 data_3
load t643 data_3
load t644 data_3
load t645 data_3
view t636_$v1 t636 1 $v1
del t636
view t637_$v1 t637 4 $v1
del t637
view t640_$v2 t640 3 $v2
del t640
view t645_$v2 t645 1 $v2
del t645
ncon t651 t639 -1,1,-2,-3 $o3 1
del t639
del $o3
ncon t652 t651 -1,1,-2 t644 1
del t651
del t644
ncon t653 t638 -1,1,-2,-3 $o2 1
del t638
del $o2
ncon t654 t653 -1,1,-2 t643 1
del t653
del t643
ncon t655 t637_$v1 -1,1,-2,-3 $o1 1
del t637_$v1
del $o1
ncon t656 t655 -1,1,-2 t642 1
del t655
del t642
ncon t657 t636_$v1 -1,1 t641 1
del t636_$v1
del t641
ncon t658 t640_$v2 -1,1,-2,-3 $o4 1
del t640_$v2
del $o4
ncon t659 t658 1,-1,-2 $o5 1
del t658
del $o5
ncon t660 t654 1,-1 t652 -2,1
del t654
del t652
ncon t661 t660 -1,1 t659 -2,1
del t660
del t659
ncon t662 t656 1,-1 t661 1,-2
del t656
del t661
ncon t663 t645_$v2 -1 t657 -2
del t645_$v2
del t657
ncon t664 t663 1,2 t662 2,1
del t663
del t662
save t664 output
