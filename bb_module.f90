MODULE bb_module

  implicit none

  PRIVATE
  PUBLIC :: bb, construct_bb

  real(8) :: bb(3,3)

CONTAINS

  SUBROUTINE construct_bb(aa)
    real(8),intent(IN) :: aa(3,3)
    real(8) :: Vaa,PI2
    PI2 = 2.d0*acos(-1.d0)
    Vaa = aa(1,1)*aa(2,2)*aa(3,3)+aa(1,2)*aa(2,3)*aa(3,1) &
         +aa(1,3)*aa(2,1)*aa(3,2)-aa(1,3)*aa(2,2)*aa(3,1) &
         -aa(1,2)*aa(2,1)*aa(3,3)-aa(1,1)*aa(2,3)*aa(3,2)
    bb(1,1) = aa(2,2)*aa(3,3) - aa(3,2)*aa(2,3)
    bb(2,1) = aa(3,2)*aa(1,3) - aa(1,2)*aa(3,3)
    bb(3,1) = aa(1,2)*aa(2,3) - aa(2,2)*aa(1,3)
    bb(1,2) = aa(2,3)*aa(3,1) - aa(3,3)*aa(2,1)
    bb(2,2) = aa(3,3)*aa(1,1) - aa(1,3)*aa(3,1)
    bb(3,2) = aa(1,3)*aa(2,1) - aa(2,3)*aa(1,1)
    bb(1,3) = aa(2,1)*aa(3,2) - aa(3,1)*aa(2,2)
    bb(2,3) = aa(3,1)*aa(1,2) - aa(1,1)*aa(3,2)
    bb(3,3) = aa(1,1)*aa(2,2) - aa(2,1)*aa(1,2)
    bb(:,:)=bb(:,:)*PI2/Vaa
  END SUBROUTINE construct_bb

END MODULE bb_module
