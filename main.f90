program main

	use init
	use timeStep
	use testmodule

	implicit none

	! print to screen
	print *, 'calling program main'

!	call cross_section
!	call Procassini
!	call test_refluxing_boundary
!	call test_anewvel_Ar
!	call test_mcc_electron
!	call test_mcc_Argon
!	call test_ext_voltage_Poisson
!   call Ar_discharge
!	call test_particle_adj(64,2)
!	call test_backward_sweep
!	call twostream
!	call Landau
	call adjoint_convergence(Landau)

	! print to screen
	print *, 'program main...done.'

contains

	! You can add custom subroutines/functions here later, if you want

	subroutine adjoint_convergence(problem)
		integer, parameter :: N=20
		real(mp) :: fk(N)
		real(mp) :: ek(N)
		integer :: i
		interface
			subroutine problem(fk,ek)
				use modPM1D
				use modAdj
				use modRecord
				real(mp), intent(in) :: fk
				real(mp), intent(out) :: ek
				type(adjoint) :: adj
				type(PM1D) :: pm
				type(recordData) :: r
			end subroutine
		end interface

		fk = (/ ( 0.1_mp**i,i=-1,N-2 ) /)
		ek = 0.0_mp


		do i=1,N
			call problem(fk(i),ek(i))
		end do

		print *, '----fk-------		---------ek----'
		do i=1,N
			print *, fk(i),ek(i),';'
		end do
	end subroutine

!   subroutine Ar_discharge
!      type(PM1D) :: pm
!      type(recordData) :: r
!      real(mp), parameter :: Kb = 1.38065E-23, EV_TO_K = 11604.52_mp, eps = 8.85418782E-12, mTorr_to_Pa = 0.13332237_mp
!      real(mp) :: I0 = 25.6_mp, I_f = 13.56E6                !I0(A/m2), If(Hz)
!      real(mp) :: TN = 0.026_mp, PN = 50.0_mp, gden        !TN(eV), PN(mTorr), gden(m-3)
!      real(mp) :: T0 = 1.0_mp, n0, f0, wp0, lambda0
!      real(mp) :: L = 0.02_mp, area = 0.016_mp               !L(m), area(m2)
!      integer, parameter :: Np = 1E6, Ng = 300
!      real(mp) :: spwt, xp0(Np), vp0(Np,3)
!      real(mp) :: dt
!      integer :: i
!      gden = (PN*mTorr_to_Pa)/(q_e*TN)
!      
!      !Saha equilibrium
!      f0 = 2.0_mp*exp(-ionengy0/T0)
!      n0 = gden*f0
!      spwt = n0*L/Np
!      
!      print *, 'gden(m-3): ',gden,', n0(m-3): ',n0,', spwt(m-2): ',spwt
!      
!      wp0 = sqrt(n0*q_e*q_e/m_e/eps)
!      lambda0 = sqrt(eps*T0/n0/q_e)
!      
!      print *, 'L = ',L,', lambda0 = ',lambda0,' e = lambda/L = ',lambda0/L
!      
!      dt = 0.1_mp/wp0
!      print *, 'dt = ',dt
!      call init_random_seed
!      call null_collision(gden,dt)
!      print *, 'P_e = ',col_prob_e,', P_Ar = ', col_prob_Ar
!      
!      call buildPM1D(pm,10000.0_mp*dt,100.0_mp*dt,Ng,2,pBC=1,mBC=2,order=1,dt=dt,L=L,eps=eps)
!      call buildRecord(r,pm%nt,2,pm%L,pm%ng,'rf_Ar',20)
!      call set_Ar_discharge(pm,(/spwt, spwt/),(/TN,gden,I0,I_f/),r)
!      call RANDOM_NUMBER(xp0)
!      vp0 = randn(Np,3)*sqrt(T0*q_e/m_e)
!      call setSpecies(pm%p(1),Np,xp0*L,vp0)
!      call RANDOM_NUMBER(xp0)
!      vp0 = randn(Np,3)*sqrt(T0*q_e/m_Ar)
!      call setSpecies(pm%p(2),Np,xp0*L,vp0)
!   
!      call forwardsweep(pm,r,RF_current,Null_source)
!
!      call printPlasma(r)
!
!      call destroyPM1D(pm)
!      call destroyRecord(r)
!   end subroutine
!
!	subroutine cross_section
!		integer, parameter :: N=10000
!		real(mp), dimension(N) :: energy, sig1, sig2, sig3, sig4, sig5
!		integer :: i
!
!		energy = exp( log(10.0_mp)*( (/ (i,i=1,N) /)/(0.2_mp*N) - 2.0_mp ) )
!		do i=1,N
!			sig1(i) = asigma1(energy(i))
!			sig2(i) = asigma2(energy(i))
!			sig3(i) = asigma3(energy(i))
!			sig4(i) = asigma4(energy(i))
!			sig5(i) = asigma5(energy(i))
!		end do
!
!		call system('mkdir -p data/cross_section')
!		open(unit=301,file='data/cross_section/sig1.bin',status='replace',form='unformatted',access='stream')
!		open(unit=302,file='data/cross_section/sig2.bin',status='replace',form='unformatted',access='stream')
!		open(unit=303,file='data/cross_section/sig3.bin',status='replace',form='unformatted',access='stream')
!		open(unit=304,file='data/cross_section/sig4.bin',status='replace',form='unformatted',access='stream')
!		open(unit=305,file='data/cross_section/sig5.bin',status='replace',form='unformatted',access='stream')
!		open(unit=306,file='data/cross_section/energy.bin',status='replace',form='unformatted',access='stream')
!		write(301) sig1
!		write(302) sig2
!		write(303) sig3
!		write(304) sig4
!		write(305) sig5
!		write(306) energy
!		close(301)
!		close(302)
!		close(303)
!		close(304)
!		close(305)
!		close(306)
!	end subroutine

	subroutine Procassini
		type(PM1D) :: sheath
		type(recordData) :: r
		real(mp), parameter :: Kb = 1.38065E-23, EV_TO_K = 11604.52_mp, eps = 8.85418782E-12
		real(mp), parameter :: Te = 50.0_mp*EV_TO_K, tau = 100.0_mp
		real(mp), parameter :: me = 9.10938215E-31, qe = 1.602176565E-19, mu = 1836
		real(mp), parameter :: n0 = 2.00000000E14
		integer, parameter :: Ne = 10000, Ni = 10000
		real(mp) :: mi, Ti, wp0, lambda0, dt, dx, L
		real(mp) :: ve0, vi0, Time_f
		real(mp) :: A(4)
		integer :: i

		mi = mu*me
		Ti = Te/tau
		wp0 = sqrt(n0*qe*qe/me/eps)
		lambda0 = sqrt(eps*Kb*Te/n0/qe/qe)
		L = 2.0_mp*lambda0

		print *, 'L = ',L,', lambda0 = ',lambda0,' e = lambda/L = ',lambda0/L

		dt = 0.1_mp/wp0
		dx = 0.2_mp*lambda0
		!		dt = 0.5_mp*dx/(lambda0*wp0)

		ve0 = sqrt(Kb*Te/me)
		vi0 = sqrt(Kb*Ti/mi)
		Time_f = 1.0_mp*L/vi0

		A = (/ ve0, vi0, 0.2_mp, 1.0_mp*Ni /)
		call buildPM1D(sheath,Time_f,0.0_mp,ceiling(L/dx),2,pBC=2,mBC=2,order=1,A=A,L=L,dt=dt,eps=eps)
		sheath%wp = wp0
		call buildRecord(r,sheath%nt,2,sheath%L,sheath%ng,'test',20)

		call buildSpecies(sheath%p(1),-qe,me,n0*L/Ne)
		call buildSpecies(sheath%p(2),qe,mi,n0*L/Ni)

		call sheath_initialize(sheath,Ne,Ni,Te,Ti,Kb)
		call forwardsweep(sheath,r,Null_input,Null_source)

		call printPlasma(r)

		call destroyRecord(r)
		call destroyPM1D(sheath)
	end subroutine

end program
