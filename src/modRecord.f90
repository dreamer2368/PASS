module modRecord

	use modPM1D

	implicit none

	type recordData
		integer :: nt, n, ng, mod
		real(mp) :: L
		character(len=:), allocatable :: dir

		integer, allocatable :: np(:,:)
		real(mp), allocatable :: phidata(:,:)
		real(mp), allocatable :: Edata(:,:)
		real(mp), allocatable :: rhodata(:,:)
		real(mp), allocatable :: PE(:), KE(:,:)
		integer, allocatable :: n_coll(:,:)               !(species*collision type, time)

		real(mp) :: cpt_temp(10)
		real(mp), allocatable :: cpt_time(:,:)
	contains
		procedure, pass(this) :: buildRecord
		procedure, pass(this) :: destroyRecord
		procedure, pass(this) :: recordPlasma
		procedure, pass(this) :: printPlasma
	end type

contains

	subroutine buildRecord(this,nt,n,L,ng,input_dir,mod)
		class(recordData), intent(out) :: this
		integer, intent(in) :: nt, n, ng, mod
		real(mp), intent(in) :: L
		character(len=*), intent(in), optional :: input_dir
		integer :: nr
		nr = nt/mod+1

		this%nt = nt
		this%n = n
		this%L = L
		this%ng = ng
		this%mod = mod

		allocate(this%np(n,nr))
		allocate(this%phidata(ng,nr))
		allocate(this%Edata(ng,nr))
		allocate(this%rhodata(ng,nr))
		allocate(this%PE(nr))
		allocate(this%KE(n,nr))
		allocate(this%cpt_time(10,nt+1))

		this%np = 0
		this%phidata = 0.0_mp
		this%Edata = 0.0_mp
		this%rhodata = 0.0_mp
		this%PE = 0.0_mp
		this%KE = 0.0_mp
		this%cpt_time = 0.0_mp

		if( present(input_dir) ) then
			allocate(character(len=len(input_dir)) :: this%dir)
			this%dir = input_dir
		else
			allocate(character(len=0) :: this%dir)
			this%dir = ''
		end if

		call system('mkdir -p data/'//this%dir//'/xp')
		call system('mkdir -p data/'//this%dir//'/vp')
		call system('mkdir -p data/'//this%dir//'/spwt')

		call system('rm data/'//this%dir//'/xp/*.*')
		call system('rm data/'//this%dir//'/vp/*.*')
		call system('rm data/'//this%dir//'/spwt/*.*')
	end subroutine

	subroutine destroyRecord(this)
		class(recordData), intent(inout) :: this
		integer :: i,j

		deallocate(this%np)
		deallocate(this%phidata)
		deallocate(this%Edata)
		deallocate(this%rhodata)

		deallocate(this%PE)
		deallocate(this%KE)

		if( allocated(this%n_coll) ) then
			deallocate(this%n_coll)
		end if

		deallocate(this%dir)
	end subroutine

	subroutine recordPlasma(this,pm,k)
		class(recordData), intent(inout) :: this
		class(PM1D), intent(in) :: pm
		integer, intent(in) :: k					!k : time step
		integer :: n,j, kr								!n : species
		character(len=100) :: nstr, kstr
		real(mp) :: qe = 1.602176565E-19

		this%cpt_time(:,k+1) = this%cpt_temp
		this%cpt_temp=0.0_mp
		if( (this%mod.eq.1) .or. (mod(k,this%mod).eq.0) ) then
			kr = merge(k,k/this%mod,this%mod.eq.1)
			do n=1,pm%n
				write(nstr,*) n
				write(kstr,*) kr
				open(unit=305,file='data/'//this%dir//'/xp/'//trim(adjustl(kstr))//'_'	&
					//trim(adjustl(nstr))//'.bin',status='replace',form='unformatted',access='stream')
				open(unit=306,file='data/'//this%dir//'/vp/'//trim(adjustl(kstr))//'_'	&
					//trim(adjustl(nstr))//'.bin',status='replace',form='unformatted',access='stream')
				open(unit=307,file='data/'//this%dir//'/spwt/'//trim(adjustl(kstr))//'_'	&
					//trim(adjustl(nstr))//'.bin',status='replace',form='unformatted',access='stream')
				write(305) pm%p(n)%xp
				write(306) pm%p(n)%vp
				write(307) pm%p(n)%spwt
				close(305)
				close(306)
				close(307)

				!time step: 0~Nt, in array: 1~(Nt+1) (valgrind prefers this way of allocation)
				this%np(n,kr+1) = pm%p(n)%np
				this%KE(n,kr+1) = 0.5_mp*pm%p(n)%ms*SUM( pm%p(n)%spwt*pm%p(n)%vp(:,1)**2 )
			end do
			this%phidata(:,kr+1) = pm%m%phi
			this%Edata(:,kr+1) = pm%m%E
			this%rhodata(:,kr+1) = pm%m%rho
			this%PE(kr+1) = 0.5_mp*SUM(pm%m%E**2)*pm%m%dx
!			this%cpt_time(:,kr+1) = this%cpt_temp

            if( print_pm_output ) then
    			print *, '============= ',k,'-th Time Step ================='
    			do n=1,pm%n
    				print *, 'Species(',n,'): ',pm%p(n)%np, ', KE: ', this%KE(n,kr+1),'J'
    			end do
                print *, 'Voltage = ',pm%m%phi(pm%ng),'V'
            end if
		end if
	end subroutine

	subroutine printPlasma(this)
		class(recordData), intent(in) :: this
		character(len=100) :: s
		integer :: i,j
		real(mp) :: total, mean, pct

		open(unit=300,file='data/'//this%dir//'/record',status='replace')
		open(unit=301,file='data/'//this%dir//'/E.bin',status='replace',form='unformatted',access='stream')
		open(unit=302,file='data/'//this%dir//'/rho.bin',status='replace',form='unformatted',access='stream')
		open(unit=303,file='data/'//this%dir//'/PE.bin',status='replace',form='unformatted',access='stream')
		open(unit=304,file='data/'//this%dir//'/Np.bin',status='replace',form='unformatted',access='stream')
		open(unit=305,file='data/'//this%dir//'/phi.bin',status='replace',form='unformatted',access='stream')
		open(unit=306,file='data/'//this%dir//'/Ncoll.bin',status='replace',form='unformatted',access='stream')
		open(unit=307,file='data/'//this%dir//'/cpt_time.bin',status='replace',form='unformatted',access='stream')
		do i=1,this%n
			write(s,*) i
			open(unit=307+i,file='data/'//this%dir//'/KE_'//trim(adjustl(s))//'.bin',status='replace',form='unformatted',access='stream')
		end do
		print *, this%n, this%ng, this%nt, this%L, this%mod
		write(300,*) this%n, this%ng, this%nt, this%L, this%mod
		close(300)

      write(306) this%n_coll
      close(306)

		write(307) this%cpt_time
		close(307)

		do i = 1,this%nt/this%mod+1
			write(301) this%Edata(:,i)
			write(302) this%rhodata(:,i)
			write(303) this%PE(i)
			write(304) this%np(:,i)
			write(305) this%phidata(:,i)
			do j=1,this%n
				write(307+j) this%KE(j,i)
			end do
		end do

		close(301)
		close(302)
		close(303)
		close(304)
		close(305)
		do i=1,this%n
			close(307+i)
		end do

701	FORMAT	(A, F10.3,'	',E10.3,'	', F10.2,'%')
		if( SUM(this%cpt_time(8,:)).eq.0.0_mp ) then
			open(unit=301,file='data/'//this%dir//'/original_cpt_summary.dat',status='replace')
			write(301,*) 'Step	Total	Mean	Percentage'
			print *, "================ Computation Time Summary ==================================="
			print *, "Original simulation	   	     Total            Mean	 Percentage	"
			total = SUM(this%cpt_time(1,:))
			mean = total/this%nt
			pct = total/SUM(this%cpt_time)*100.0_mp
			print 701, "Particle Move			", total, mean, pct
			write(301,701) 'Particle-Move	', total, mean, pct
			total = SUM(this%cpt_time(2,:))
			mean = total/this%nt
			pct = total/SUM(this%cpt_time)*100.0_mp
			print 701, "ApplyBC				", total, mean, pct
			write(301,701) 'ApplyBC	', total, mean, pct
			total = SUM(this%cpt_time(3,:))
			mean = total/this%nt
			pct = total/SUM(this%cpt_time)*100.0_mp
			print 701, "ChargeAssign			", total, mean, pct
			write(301,701) 'Charge-Assign	', total, mean, pct
			total = SUM(this%cpt_time(4,:))
			mean = total/this%nt
			pct = total/SUM(this%cpt_time)*100.0_mp
			print 701, "Poisson Solver			", total, mean, pct
			write(301,701) 'Poisson-Solver	', total, mean, pct
			total = SUM(this%cpt_time(5,:))
			mean = total/this%nt
			pct = total/SUM(this%cpt_time)*100.0_mp
			print 701, "Efield Gradient			", total, mean, pct
			write(301,701) 'Efield-Gradient	', total, mean, pct
			total = SUM(this%cpt_time(6,:))
			mean = total/this%nt
			pct = total/SUM(this%cpt_time)*100.0_mp
			print 701, "Force Assign			", total, mean, pct
			write(301,701) 'Force-Assign	', total, mean, pct
			total = SUM(this%cpt_time(7,:))
			mean = total/this%nt
			pct = total/SUM(this%cpt_time)*100.0_mp
			print 701, "Particle Accel			", total, mean, pct
			write(301,701) 'Particle-Accel	', total, mean, pct
			print *, "============================================================================="
			close(301)
		else
			open(unit=301,file='data/'//this%dir//'/sensitivity_cpt_summary.dat',status='replace')
			write(301,*) 'Step	Total	Mean	Percentage'
			print *, "================ Computation Time Summary ==================================="
			print *, "Sensitivity simulation	  	     Total            Mean   	 Percentage	"
			total = SUM(this%cpt_time(1,:))
			mean = total/this%nt
			pct = total/SUM(this%cpt_time)*100.0_mp
			print 701, "Particle Move			", total, mean, pct
			write(301,701) 'Particle-Move	', total, mean, pct
			total = SUM(this%cpt_time(2,:))
			mean = total/this%nt
			pct = total/SUM(this%cpt_time)*100.0_mp
			print 701, "ApplyBC				", total, mean, pct
			write(301,701) 'ApplyBC	', total, mean, pct
			total = SUM(this%cpt_time(3,:))
			mean = total/this%nt
			pct = total/SUM(this%cpt_time)*100.0_mp
			print 701, "ChargeAssign			", total, mean, pct
			write(301,701) 'Charge-Assign	', total, mean, pct
			total = SUM(this%cpt_time(4,:))
			mean = total/this%nt
			pct = total/SUM(this%cpt_time)*100.0_mp
			print 701, "Poisson Solver			", total, mean, pct
			write(301,701) 'Poisson-Solver	', total, mean, pct
			total = SUM(this%cpt_time(5,:))
			mean = total/this%nt
			pct = total/SUM(this%cpt_time)*100.0_mp
			print 701, "Efield Gradient			", total, mean, pct
			write(301,701) 'Efield-Gradient	', total, mean, pct
			total = SUM(this%cpt_time(6,:))
			mean = total/this%nt
			pct = total/SUM(this%cpt_time)*100.0_mp
			print 701, "Force Assign			", total, mean, pct
			write(301,701) 'Force-Assign	', total, mean, pct
			total = SUM(this%cpt_time(7,:))
			mean = total/this%nt
			pct = total/SUM(this%cpt_time)*100.0_mp
			print 701, "Particle Accel			", total, mean, pct
			write(301,701) 'Particle-Accel	', total, mean, pct
			total = SUM(this%cpt_time(8,:))
			mean = total/this%nt
			pct = total/SUM(this%cpt_time)*100.0_mp
			print 701, "Sensitivity Source		", total, mean, pct
			write(301,701) 'Sensitivity-Source	', total, mean, pct
			total = SUM(this%cpt_time(9,:))
			mean = total/this%nt
			pct = total/SUM(this%cpt_time)*100.0_mp
			print 701, "Injection			", total, mean, pct
			write(301,701) 'Injection	', total, mean, pct
			total = SUM(this%cpt_time(10,:))
			mean = total/this%nt
			pct = total/SUM(this%cpt_time)*100.0_mp
			print 701, "Remeshing			", total, mean, pct
			write(301,701) 'Remeshing	', total, mean, pct
			print *, "============================================================================="
			close(301)
		end if
	end subroutine

!=======================================================
!	For no_collision: don't compute n_coll
!=======================================================

	subroutine set_null_discharge(r)
		type(recordData), intent(inout), optional :: r

		if( present(r) ) then
			allocate(r%n_coll(1,r%nt))
			r%n_coll = 0
		end if
	end subroutine

end module