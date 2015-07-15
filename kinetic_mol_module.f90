MODULE kinetic_mol_module

  use rgrid_mol_module, only: LL
  use bc_module, only: www, bcset, bcset_1
  use kinetic_variables, only: coef_lap0, coef_lap, Md

  implicit none

  PRIVATE
  PUBLIC :: op_kinetic_mol

CONTAINS

  SUBROUTINE op_kinetic_mol(n1,n2,ib1,ib2,tpsi,htpsi)
    implicit none
    integer,intent(IN) :: n1,n2,ib1,ib2
#ifdef _DRSDFT_
    real(8),intent(IN)    ::  tpsi(n1:n2,ib1:ib2)
    real(8),intent(INOUT) :: htpsi(n1:n2,ib1:ib2)
#else
    complex(8),intent(IN)    ::  tpsi(n1:n2,ib1:ib2)
    complex(8),intent(INOUT) :: htpsi(n1:n2,ib1:ib2)
#endif
    integer :: i,ib,i1,i2,i3,m,n

    do ib=ib1,ib2
!$OMP do
       do i=n1,n2
          www( LL(1,i),LL(2,i),LL(3,i),ib-ib1+1 ) = tpsi(i,ib)
       end do
!$OMP end do
    end do

!!$OMP single
!    call bcset(1,ib2-ib1+1,Md,0)
!!$OMP end single
!$OMP barrier
    call bcset_1(1,ib2-ib1+1,Md,0)
!$OMP barrier

    do ib=ib1,ib2
!$OMP do
       do i=n1,n2
          htpsi(i,ib) = htpsi(i,ib) + coef_lap0*tpsi(i,ib)
       end do
!$OMP end do
    end do

    do ib=ib1,ib2
       n=ib-ib1+1
       do m=1,Md
!$OMP do
          do i=n1,n2
             i1=LL(1,i)
             i2=LL(2,i)
             i3=LL(3,i)
             htpsi(i,ib)=htpsi(i,ib) &
                  +coef_lap(1,m)*( www(i1+m,i2,i3,n)+www(i1-m,i2,i3,n) ) &
                  +coef_lap(2,m)*( www(i1,i2+m,i3,n)+www(i1,i2-m,i3,n) ) &
                  +coef_lap(3,m)*( www(i1,i2,i3+m,n)+www(i1,i2,i3-m,n) )
          end do
!$OMP end do
       end do
    end do
 
  END SUBROUTINE op_kinetic_mol

END MODULE kinetic_mol_module
