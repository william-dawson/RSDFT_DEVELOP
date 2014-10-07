MODULE ForceSub
  implicit none
  integer :: a1b,a2b,a3b,ab1,ab2,ab3
  integer :: ML1,ML2,ML3
  real(8) :: c1,c2,c3
  real(8) :: d1,d2,d3
  logical,allocatable :: isAtomInThisNode(:)
  logical :: notAtom
  integer :: a,L,m,iorb,ik
  real(8) :: Rx,Ry,Rz
  real(8) :: x,y,z,r

CONTAINS
!-------------------------------------------------------------------------
  SUBROUTINE setLocalIndexForBoundary(Igrid)
    implicit none
    integer,intent(IN) :: Igrid(2,3)
    a1b=Igrid(1,1)
    a2b=Igrid(1,2)
    a3b=Igrid(1,3)
    ab1=Igrid(2,1)-Igrid(1,1)+1
    ab2=Igrid(2,2)-Igrid(1,2)+1
    ab3=Igrid(2,3)-Igrid(1,3)+1
  END SUBROUTINE setLocalIndexForBoundary
!-------------------------------------------------------------------------
  SUBROUTINE setConstGridWidth(Ngrid)
    implicit none
    integer,intent(IN) :: Ngrid(3)
    ML1 = Ngrid(1)
    ML2 = Ngrid(2)
    ML3 = Ngrid(3)
    c1=1.d0/ML1
    c2=1.d0/ML2
    c3=1.d0/ML3
  END SUBROUTINE setConstGridWidth
!-------------------------------------------------------------------------
  SUBROUTINE setLocalAtoms(maxAtom,aa_atom,Igrid)
    implicit none
    integer,intent(IN) :: maxAtom
    real(8),intent(IN) :: aa_atom(3,maxAtom)
    integer,intent(IN) :: Igrid(2,3)
    integer :: ia
    integer :: i1,i2,i3
    real(8) :: k1,k2,k3
    allocate( isAtomInThisNode(maxAtom) ) ; isAtomInThisNode=.false.
!$OMP parallel
!$OMP do private( i1,i2,i3,k1,k2,k3 )
    do ia=1,maxAtom
      i1 = nint( aa_atom(1,ia)*ML1 )
      i2 = nint( aa_atom(2,ia)*ML2 )
      i3 = nint( aa_atom(3,ia)*ML3 )
      k1 = i1/ML1 ; if ( i1<0 ) k1=(i1+1)/ML1-1
      k2 = i2/ML2 ; if ( i2<0 ) k2=(i2+1)/ML2-1
      k3 = i3/ML3 ; if ( i3<0 ) k3=(i3+1)/ML3-1
      i1 = i1 - k1*ML1
      i2 = i2 - k2*ML2
      i3 = i3 - k3*ML3
      if ( Igrid(1,1) <= i1 .and. i1 <= Igrid(2,1) .and. &
          Igrid(1,2) <= i2 .and. i2 <= Igrid(2,2) .and. &
          Igrid(1,3) <= i3 .and. i3 <= Igrid(2,3) ) then
        isAtomInThisNode(ia)=.true.
      end if
    end do
!$OMP end do
!$OMP end parallel
  END SUBROUTINE setLocalAtoms
!-------------------------------------------------------------------------
  SUBROUTINE getAtomInfoFrom_lma(lma)
    use ps_nloc2_variables, only: amap,lmap,mmap,iorbmap
    use atom_module, only: ki_atom
    implicit none
    integer,intent(IN) :: lma
    notAtom=.false.
    a     = amap(lma)
    if (a<=0) then
      notAtom=.true.
      return
    endif
    L     = lmap(lma)
    m     = mmap(lma)
    iorb  = iorbmap(lma)
    ik    = ki_atom(a)
  END SUBROUTINE getAtomInfoFrom_lma
!-------------------------------------------------------------------------
  SUBROUTINE getAtomPosition_real
    use atom_module, only: aa_atom
    use aa_module, only: aa
    implicit none
    Rx=aa(1,1)*aa_atom(1,a)+aa(1,2)*aa_atom(2,a)+aa(1,3)*aa_atom(3,a)
    Ry=aa(2,1)*aa_atom(1,a)+aa(2,2)*aa_atom(2,a)+aa(2,3)*aa_atom(3,a)
    Rz=aa(3,1)*aa_atom(1,a)+aa(3,2)*aa_atom(2,a)+aa(3,3)*aa_atom(3,a)
  END SUBROUTINE getAtomPosition_real
!-------------------------------------------------------------------------
  SUBROUTINE getAtomCenteredPositionFrom_lma(lma,j)
    use ps_nloc2_variables, only: JJ_MAP
    use aa_module, only: aa
    implicit none
    integer,intent(IN) :: lma,j
!    real(8) :: d1,d2,d3
    d1=c1*JJ_MAP(1,j,lma)+JJ_MAP(4,j,lma)
    d2=c2*JJ_MAP(2,j,lma)+JJ_MAP(5,j,lma)
    d3=c3*JJ_MAP(3,j,lma)+JJ_MAP(6,j,lma)
    x = aa(1,1)*d1+aa(1,2)*d2+aa(1,3)*d3-Rx
    y = aa(2,1)*d1+aa(2,2)*d2+aa(2,3)*d3-Ry
    z = aa(3,1)*d1+aa(3,2)*d2+aa(3,3)*d3-Rz
    r = sqrt(x*x+y*y+z*z)
  END SUBROUTINE getAtomCenteredPositionFrom_lma
!-------------------------------------------------------------------------
  SUBROUTINE interpolate_dviod
    use VarPSMember, only: rad1,dviod
    implicit none
#ifdef _SPLINE_
    if ( r < rad1(2,ik) ) then
      tmp0=dviod(2,lm1,ik)/(rad1(2,ik)**2)
    else
      call splint(rad1(1,ik),dviod(1,lm1,ik),y2b,NRc,r,tmp0)
      tmp0=tmp0/(r*r)
    end if
#else
    if ( ir <= 2 ) then
      err0=0.d0
      tmp0=dviod(2,lm1,ik)/(rad1(2,ik)**2)
      if ( ir < 1 ) stop "calc_force_ps_nloc_uspp"
    else if ( ir <= NRc ) then
      err0=1.d10
      do im=1,20
        m1=max(1,ir-im)
        m2=min(ir+im,NRc)
        call polint(rad1(m1,ik),dviod(m1,lm1,ik),m2-m1+1,r,tmp1,err)
        if ( abs(err)<err0 ) then
          tmp0=tmp1
          err0=abs(err)
          if ( err0<ep ) exit
        end if
      end do
      tmp0=tmp0/(r*r)
    else
      write(*,*) "force_ps_nloc_uspp",ir,NRc
      stop
    end if
    maxerr=max(maxerr,err0)
#endif

  END SUBROUTINE interpolate_dviod

END MODULE ForceSub
