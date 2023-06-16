#include <sys/sysctl.h>
#include "kdebug.h"
#include "kdebug_private.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>


/**
  * KDebugView - 0.2
  *
  * Basic version (no filters, no raw output)
  *
  *
  * No license, so you can go use and abuse
  *
  * (Though a greet would be appreciated :-)
  *
  * J@NewOSXBook.com
  *
  */

struct kinfo_proc * getProcNames(int *HowMany);
int g_my_pid = 0;
int g_filtered_pid = -1;

// Classes to text - based on sys/kdebug.h, and a bit of reversing
//
static const char *kdebugClasses[] =
{
  "0",
  "MACH",    // #define DBG_MACH                1
  "NETWORK", // #define DBG_NETWORK             2       
  "FSYSTEM", // #define DBG_FSYSTEM             3
  "BSD",     // #define DBG_BSD                 4
  "IOKIT",   // #define DBG_IOKIT               5
  "DRIVERS", // #define DBG_DRIVERS             6
  "TRACE",   // #define DBG_TRACE               7
  "DLIL",    // #define DBG_DLIL                8
  "WORKQUEUE", // #define DBG_WORKQUEUE, formerly (< 10.10) _SECURITY,   
  "CORESTO", // #define DBG_CORESTORAGE         10
  "COREGR",   // #define DBG_CG                  11
  "12?", "13?", "14?","15?", "16?", "17?", "18?", "19?", 
  "MISC",    // #define DBG_MISC                20
  "21?","22?", "23?", "24?","25?", "26?", "27?", "28?", "29?", 
  "SECURITY", // As of 10.10
  "DYLD",    // #define DBG_DYLD                31
  "QT",      // #define DBG_QT                  32
  "APPS",    // #define DBG_APPS                33
  "LAUNCHD", // #define DBG_LAUNCHD             34
  "35?",      // 
  "HANGTRACER",      // iOS 9: undocumented
  "PERF" ,    // #define DBG_PERF                37
  // added in 10.9
  "IMPORTANCE",  // #define DBG_IMPORTANCE          38
  "39?", // Apparently present in iOS?
  // Added in 10.10
  "BANK",    // #define DBG_BANK                40
  "XPC",     //#define DBG_XPC                 41
  "ATM" ,    // #define DBG_ATM                 42
  "ARIADNE", // #define DBG_ARIADNE             43
  // Added in 10.11
  "DAEMON",  // #define DBG_DAEMON              44
  "ENERGY",  // #define DBG_ENERGYTRACE         45
  "46?", "47?","48?",
  "49 (11,9)?", // used in 10.11 by apps and in 9 also by kernel_task
  "50?","51?","52?","53?","54?","55?","56?","57?","58?","59?",
  "60?","61?","62?","63?","64?","65?","66?","67?","68?","69?",
  "70?","71?","72?","73?","74?","75?","76?","77?","78?","79?",
  "80?","81?","82?","83?","84?","85?","86?","87?","88?","89?",
  "90?","91?","92?","93?","94?","95?","96?","97?","98?","99?",
  "100?","101?","102?","103?","104?","105?","106?","107?","108?","109?",
  "110?","111?","112?","113?","114?","115?","116?","117?","118?","119?",
  "120?","121?","122?","123?","124?","125?","126?","127?","128?","129?",
  "130?","131?","132?","133?","134?","135?","136?","137?","138?","139?",
  "140?","141?","142?","143?","144?","145?","146?","147?","148?","149?",
  "150?","151?","152?","153?","154?","155?","156?","157?","158?","159?",
  "160?","161?","162?","163?","164?","165?","166?","167?","168?","169?",
  "WINDOWSERVER", // apparently deprecated in 10.11 and merged with 49
  "171?","172?","173?","174?","175?","176?","177?","178?","179?",
  "180?","181?","182?","183?","184?","185?","186?","187?","188?","189?",
  "190?","191?","192?","193?","194?","195?","196?","197?","198?","199?",
  "200?","201?","202?","203?","204?","205?","206?","207?","208?","209?",
  "210?","211?","212?","213?","214?","215?","216?","217?","218?","219?",
  "220?","221?","222?","223?","224?","225?","226?","227?","228?","229?",
  "230?","231?","232?","233?","234?","235?","236?","237?","238?",
  "IOS_APPS", // iOS: Used by tons of Apps, undocumented
  "240?","241?","242?","243?","244?","245?","246?","247?","248?","249?",
  "250?","251?","252?","253?","254?",
  "MIG", // #define DBG_MIG                 255
}; // kdebugClasses


// Globals:

int mib[7];

int kdebugEnabled = 0;
size_t len = 4;

int output = 0 ; // the FD we dump everything into


#pragma mark "Near-verbatim copy of Apple's fs_usage/sc_usage

// The following kdebug[A-Z]* functions are essentially the same as in Apple's tools.
//
// Before certain kind-hearted souls think of complaining:
//    A) This is pretty much the only way to setup kdebug.
//    B) I did credit Apple
//

int kdebugInit()
{

        kd_regtype kr;

        kr.type = KDBG_RANGETYPE;
        kr.value1 = 0;
        kr.value2 = -1;
	kr.value3 = kr.value4 = 0;
        size_t needed = sizeof(kd_regtype);

        mib[0] = CTL_KERN;
        mib[1] = KERN_KDEBUG;
        mib[2] = KERN_KDSETREG;         
        mib[3] = 0;
        mib[4] = 0;
        mib[5] = 0;  

        if (sysctl(mib, 3, &kr, &needed, NULL, 0) < 0) { perror ("KERN_KDSETREG"); exit(2);}

        mib[0] = CTL_KERN;
        mib[1] = KERN_KDEBUG;
        mib[2] = KERN_KDSETUP;          
        mib[3] = 0;
        mib[4] = 0;
        mib[5] = 0;         

        if (sysctl(mib, 3, NULL, &needed, NULL, 0) < 0) { perror ("KERN_KDSETUP"); exit(3);}


	return 0;
}


int kdebugBufs(int bufs)
{


    // Buffers
    
    mib[0] = CTL_KERN;
    mib[1] = KERN_KDEBUG;
    mib[2] = KERN_KDSETBUF;
    mib[3] = 8192 *1024; // So we don't miss anything

    if ((sysctl(mib, 4, NULL, &len, NULL, 0) < 0)) {
        perror ("KDSETBUF"); exit(4);
    }

    mib[0] = CTL_KERN;
    mib[1] = KERN_KDEBUG;
    mib[2] = KERN_KDSETUP;
    if (sysctl(mib, 3, NULL, &len, NULL, 0) < 0)
    { perror ("KDSETUP"); exit(5);}
 
    
   return 0;   
}


int kdebugEnable(int enable)
{
    
	// Now do enable
   
    mib[0] = CTL_KERN;
    mib[1] = KERN_KDEBUG;
    mib[2] =  KERN_KDENABLE ; // 14
    mib[3] = 1;
     
  
    if ((sysctl(mib, 4, NULL, 0, NULL, 0) < 0)) {
        fprintf(stderr,"ERROR in kdebugEnable: KDENABLE");
        perror("sysctl");
        return 1;}
    
      printf("KDebug Enabled\n");
    

    
    kdebugEnabled = enable;
    return 0;
}

#pragma mark "Back to J's code"

unsigned long kp_nentries = 0;

struct kinfo_proc * getProcNames(int *howMany)
{
    size_t                  bufSize = 0;
    struct kinfo_proc       *kp;
    
    mib[0] = CTL_KERN;
    mib[1] = KERN_PROC;
    mib[2] = KERN_PROC_ALL;
    mib[3] = 0;
    
    if (sysctl(mib, 4, NULL, &bufSize, NULL, 0) < 0) { perror ("KERN_PROC_ALL"); exit(20); }
    
    if ((kp = (struct kinfo_proc *)malloc(bufSize)) == (struct kinfo_proc *)0) { perror("malloc of kinfo_proc"); exit(21); }
    
    if (sysctl(mib, 4, kp, &bufSize, NULL, 0) < 0) { perror("KERN_PROC_ALL"); exit(22); }
    
    *howMany  = bufSize/ sizeof(struct kinfo_proc);
    return (kp);
    
}




typedef struct {
        uintptr_t       thread;
        int             valid;
        char            command[20];
	pid_t		pid;
	int		certain;

} jl_threadmap;


kd_threadmap *threadMap = NULL;
jl_threadmap *my_threadMap = NULL;


jl_threadmap *lookupThread (uint32_t	tid, jl_threadmap *tm)
{
	if (!tm) return (NULL);
	int t = 0;
          while (tm[t].thread)
            {
		if (tm[t].thread == tid) return (&tm[t]);
		t++;
	    }

	return (NULL);

}

void updateThreadCommand (uint64_t tid, jl_threadmap *tm, char *command, pid_t pid)
{
	if (!tm)  {printf("UPD: NO THREAD MAP?\n"); return;};
	if (!command)  {printf ("UPD: NO COMMAND?!\n");return;};
	int t = 0;
          while (tm[t].thread)
            {
		if (tm[t].thread == tid) { 
			printf("UPDATING %llu to %s - PID %d (%d)\n", tid, command,pid, tm[t].pid);
		 	   if (pid) {tm[t].pid = pid;}
			   strncpy (tm[t].command, command, 20);return;
			}

		t++;
   
	   }

	// Otherwise here, write. @TOD: Worry about mem corruption later..
	printf("UPDATING %llu to %s, PID = %d\n", tid, command,pid);

	tm[t].thread = tid;
 	strncpy(tm[t].command, command, 20); return;
	tm[t].pid = pid;

}


kbufinfo_t kbufinfo;

void getBufInfo(void)
{
    size_t needed = sizeof(kbufinfo_t);;
    
    mib[0] = CTL_KERN;
    mib[1] = KERN_KDEBUG;
    mib[2] = KERN_KDGETBUF;
    mib[3] = 0;
    
    
    
    if (sysctl(mib, 3, &kbufinfo, &needed, 0, 0) < 0) { perror("failure in  KERN_KDGETBUF\n"); exit(1);}
} // getBufIn

jl_threadmap *readThreadMap(void)
{
    // Read thread map, too:
    

    if (threadMap) free(threadMap);
    
    

    int numProcs = 0;
    struct kinfo_proc *procNames = getProcNames(&numProcs);
    
    getBufInfo();
  
    int num_threads = kbufinfo.nkdthreads;
    size_t size = kbufinfo.nkdthreads *  sizeof(kd_threadmap);

    
    printf("NUM THREADS: %d - size %ld\n", num_threads,size);
  
 
    threadMap = (kd_threadmap *) calloc(size, 1);
    my_threadMap = (jl_threadmap *) calloc(num_threads * 2 * sizeof (jl_threadmap), 1);
    
    // but lie to kdebug and say we allocated just enough (else EINVAL!)



    if (threadMap){

	printf("Allocated Threadmap of %zu bytes, %p\n", size,threadMap);
        
	memset (threadMap, '\0', size);

        mib[0] = CTL_KERN;
        mib[1] = KERN_KDEBUG;
        mib[2] = KERN_KDTHRMAP; //READCURTHRMAP;

  

        if (sysctl(mib, 3, threadMap, &size, NULL, 0) < 0) {
            perror("--Unable to read thread map");
            free(threadMap);
            threadMap = NULL;
            
        	}
        }
        if (threadMap){
		fprintf(stderr, "Read Thread Map...\n");
            int t = 0;
            // Dump thread Map:

	    bzero(my_threadMap, sizeof (my_threadMap));

            while (threadMap[t].thread)
            {
                memcpy(&my_threadMap[t], &threadMap[t], sizeof (kd_threadmap));
		// Try to figure out PID

		for (int p = 0;
		     p < numProcs; p++)
		{
			if (strcmp(procNames[p].kp_proc.p_comm,
			           my_threadMap[t].command) == 0)
			{ // printf ("found %s -%d \n", procNames[p].kp_proc.p_comm, procNames[p].kp_proc.p_pid); 
			  
			   if (my_threadMap[t].pid) {
				my_threadMap[t].certain = 0;
				strcat (my_threadMap[t].command,"!");
				}
			    else {
			    my_threadMap[t].pid = procNames[p].kp_proc.p_pid;
				my_threadMap[t].certain = 1;
				}
		
			}
			
		}
		t++;
            }
            
        }
    
   return(my_threadMap);
}

void kdebugRemove()
{
    size_t size = 3;
    mib[0] = CTL_KERN;
    mib[1] = KERN_KDEBUG;
    mib[2] = KERN_KDREMOVE;
    int rc = sysctl(mib,3, NULL,&size, NULL,0);
    
    if (rc != 0) { perror ("KDREMOVE"); exit(6);}
}

void cleanup()
{
    size_t size =4;
    int mib[4];
    
   if (!kdebugEnabled) return;

   fprintf(stderr,"\nCleaning up\n");

    mib[0] = CTL_KERN;
    mib[1] = KERN_KDEBUG;
    mib[2] =  KERN_KDENABLE ; // 14
    mib[3] = 0;
    
    if ((sysctl(mib, 4, NULL, 0, NULL, 0) < 0)) {
        fprintf(stderr,"ERROR in kdebugEnable: KDENABLE");
        perror("sysctl");
        return;}
    


    kdebugRemove();

    close(output);
	
    exit(0);

}
int kdebugRead(unsigned char *buf, unsigned long *len)
{
   mib[0] = CTL_KERN;
   mib[1] = KERN_KDEBUG;
   mib[2] = KERN_KDREADTR;
    int rc;
    if ((rc =sysctl(mib, 3, buf, len, NULL, 0)) < 0)
    {
	fprintf(stderr,"Error in read - %s\n", strerror (errno));
        perror ("sysctl");
    }
    return (rc);
}



void handler (int signum)
{
    cleanup();
    
}

#define TRACE_CODES_FILE "/usr/share/misc/trace.codes"

char *trace_codes_filename = TRACE_CODES_FILE;


struct codeDesc {
	uint32_t	code;
	char		desc[128];
		};

struct codeDesc codes[5000];

void loadTraceCodes(char *FileName)
{

	memset (codes, '\0', sizeof (codes));

	int def = 0;
	if (!FileName) {FileName = trace_codes_filename; def = 1;}

	FILE *traceCodesFile = fopen (FileName, "r");

	if (!traceCodesFile)
	{
		
		if (def) { fprintf(stderr,"Warning: Unable to load default trace codes file\n"); }
		else { fprintf(stderr,"Warning: Unable to load specified trace codes file %s\n", FileName);}
		return;
	
 	}

	char buf[1024];
	fgets(buf,  // char * restrict str, 
	      1024, // int size, 
	      traceCodesFile); // FILE * restrict stream);

	int codeNum = 0;
        int rc = 0;
	int comments = 0;

	int malformed = 0;
	int lineNo = 1;
	while (!feof (traceCodesFile))
	{
		rc = sscanf (buf, "%x %s\n", &(codes[codeNum].code), (codes[codeNum].desc));
		if (rc !=2 ) {
		  	if (buf[0] == '#') { comments++; // this is a comment line, ignore };
		   }
		  else
			{
			fprintf (stderr,"Warning: trace codes file %s is malformed - line %d\n", FileName, lineNo);
			malformed++;
			}

		}
		else
		{
			codeNum++;

		}

		lineNo++;
		
	//	printf("CODE: %x, Desc: %s \n", codes[codeNum].code, codes[codeNum].desc);

 		fgets(buf,  // char * restrict str, 
		      1024, // int size, 
		      traceCodesFile); // FILE * restrict stream);

	}

	// Only output this if codes were loaded at all - we have warnings for partial/no load cases

	if (codeNum) { fprintf (stderr,"Loaded %d/%d codes\n", codeNum, codeNum - malformed); }
}

static inline const char *lookupCode (uint32_t Code)
{
	int codeNum = 0 ;
	// make sure Code is without func qualifiers
	Code &= 0xfffffffc;

	while (codes[codeNum].code) 
	{
		if (codes[codeNum].code == Code) return (codes[codeNum].desc);
		codeNum++;
	}

	// At least try through the class table we have 

	return (kdebugClasses[ Code >> 24]);

}

#ifdef ARM
#define NUMCHUNKS	1
#define BUFCHUNK	(65536 * 64)
#else
#define NUMCHUNKS	64
#define BUFCHUNK	(65536 * 64)
#endif

int g_pid = 0 ;
char *g_procName = NULL;

void reader(unsigned char *buf)
{
 
    unsigned long bufSize = BUFCHUNK;
    unsigned long used = bufSize;
    
    output = open ("/tmp/output", O_CREAT | O_WRONLY); 
    fchmod(output, S_IRUSR | S_IWUSR);
    
    int offset = 0;
    int bufNum = 0;
    
    uint64_t base = 0;
   
    int everything  = 1;
    int cpu = 0;

    getBufInfo();
    while (kdebugRead(buf , &used) == 0) {

	if (used == 0) { used = bufSize; continue;}
	//printf ("Read %d bytes to %d\n", bufSize, bufNum);
        kd_buf *kd = (kd_buf *) (buf); // +offset);
        kdebugCode *code;
	
	write (output, buf, used);

	// Do the following if we loaded codes - otherwise, skip, and just log to output
	if (codes[0].code) 
	{
		int i = 0;

		if (!base) { base = kd[0].timestamp & KDBG_TIMESTAMP_MASK;}
		
		int lastExecThread = 0;
		int lastExecPid = 0;
		char *procName;

		int pid = 0;
		for (i = 0;  i  < used ; i++)
		{
		   code = (kdebugCode *)&kd[i].debugid;
		   jl_threadmap  *th = lookupThread(kd[i].arg5,my_threadMap);
		   if (th)
		   {
		   	pid = th->pid;
			procName = th->command;
		   }
		   else
		   {
			pid = 0;
			procName = "???";
		   }
		

#ifndef ARMv7
		cpu = kd[i].cpuid; // (kd[i].timestamp & KDBG_CPU_MASK >>  KDBG_CPU_SHIFT);
#else
		cpu = 0;
#endif

		const char *code;
		switch (kd[i].debugid)
		{
			case TRACE_DATA_EXEC:
			{
			  lastExecThread = kd[i].arg5;
			   lastExecPid = kd[i].arg1;

			  printf ("UPD: EXEC  by %lx,  PID %lu \n", kd[i].arg5, kd[i].arg1);
			  updateThreadCommand(kd[i].arg5, my_threadMap, "exec", kd[i].arg1);
		
			}
			break;
		  	case TRACE_DATA_NEWTHREAD:
		    {
	            //updateThreadCommand(kd[i].arg5, my_threadMap, (char *) &kd[i].arg1, 0);
                    }
			break;


			case TRACE_STRING_EXEC:
			{ 
			  printf ("UPD: EXEC of  %s - by %lu, tm = %p \n", (char *)&kd[i].arg1, kd[i].arg5, threadMap);
			updateThreadCommand (kd[i].arg5, my_threadMap,  (char *)&kd[i].arg1, 0);
			lastExecThread = 0 ;
			lastExecPid = 0 ;
			}
			break;

		   default:
		  code =lookupCode(kd[i].debugid);

			  if (pid == g_my_pid) continue;
			  if (g_filtered_pid >=0 && g_filtered_pid != pid) continue;

		  if ((kd[i].debugid & 0xff000000) == 0xff000000)
			{
			  uint32_t msg = ((kd[i].debugid) & 0x00ffffff) >> 2;

			  char *func = "?";
			  if (kd[i].debugid &0x1) func = "start";
			  if (kd[i].debugid &0x2) func = "end";
		
			  printf ("%lld %d %08x MIG MSG: %d %s\t%s/%lu/0x%lx\tArgs:%lx %lx %lx %lx\n", 
			  (kd[i].timestamp & KDBG_TIMESTAMP_MASK) - base , 
			        cpu,
				kd[i].debugid,
				msg,
				func,
				procName,  pid, kd[i].arg5, 
				kd[i].arg1, kd[i].arg2, kd[i].arg3,kd[i].arg4);

			}
		  //else
		  char codeStr[32];
		  if (everything)
			{ 
			  // @TODO: Move filtering to PIDEX, PIDTR

			  char dir = ' ';
			  if (kd[i].debugid & DBG_FUNC_START) { dir = '>';}
			  if (kd[i].debugid & DBG_FUNC_END) { dir = '<'; }

			  strncpy(codeStr, lookupCode(kd[i].debugid),30);
			  codeStr[31] ='\0';
	
			  printf("%lld %d 0x%08x %c %-20s\t%s/%lu/0x%lx\tArgs:%lx %lx %lx %lx \n", 
			  (kd[i].timestamp & KDBG_TIMESTAMP_MASK) - base , 
			  cpu,
		   	  kd[i].debugid, dir, codeStr, procName, pid, kd[i].arg5, kd[i].arg1, kd[i].arg2, kd[i].arg3, kd[i].arg4);
			}
	
		} // end switch

		} // end for 

		if (kbufinfo.flags & KDBG_WRAPPED) { fprintf(stderr, "WHOA, nelly! Too many events!\n"); }

		//fprintf(stderr,"Next iter (Used: %d , Flags: 0x%x\n", used, kbufinfo.flags);
		used = bufSize;

	} // codes[codeNum].code

	offset = 0;

    }


}


#define PID_INCLUDE	1
#define PID_EXCLUDE	2
#define PID_DEFAULT	0

void filterPID(int pid, int includeExclude)
{

	

	int code = 1;
	char *incExc = "?";
	switch (includeExclude)
	{
		case PID_INCLUDE: incExc = "including"; code = KERN_KDPIDTR; break;
		case PID_EXCLUDE: incExc = "excluding"; code = KERN_KDPIDEX; break;
		case PID_DEFAULT: /* @TODO */; break;
	}


 kd_regtype kr;

        kr.type = KDBG_TYPENONE;
        kr.value1 = pid;
        kr.value2 = 1;
	kr.value3 = kr.value4 = 0;
   	int     needed = sizeof(kd_regtype);
        mib[0] = CTL_KERN;
        mib[1] = KERN_KDEBUG;
        mib[2] = code;
        mib[3] = 0;
        mib[4] = 0;
        mib[5] = 0;
        if (sysctl(mib, 3, &kr, &needed, NULL, 0) < 0) {
                        printf("pid %d does not exist\n", pid);
                        exit(2);
                }



	printf ("%s PID %d\n", incExc, pid);
}



#define VERSION		"0.2"

void printUsage(char *Name)
{
	fprintf(stderr,"Usage: %s [_pid_|all]\n", Name);
	fprintf(stderr,"Where: _pid_      : optional PID to trace (all threads will be traced). Set to 0 for kernel_task :-)\n");
	fprintf(stderr,"       all        : Trace ALL pids (TONS of output!)\n");
#if 0
	fprintf(stderr,"       -f _filter_: Specify filter. Currently defined filters are:\n");
	fprintf(stderr,"                    msg: Mach messages\n");
	fprintf(stderr,"                    (though I would suggest filtering a posteriori by using grep(1))\n");
#endif
	fprintf(stderr,"\nThis is J's kdebugview version " VERSION ". Based on Apple's system_cmd's fs_usage(1), sc_usage(1), and trace(1).\nGet the latest version (+ source) at http://NewOSXBook.com/tools/kdv.html\nComments/Feature Requests always welcome at http://NewOSXBook.com/forum/\n");
}

int main (int argc, char **argv)
{

    int i ;

    int rc = 0;


    int pid = -2;


    if (argc < 2)
	{
		printUsage(argv[0]);
		exit(0);
	}

    for (i = 1; i < argc; i++)
	{
    	   if (argv[i][0] != '-')
		{
			
			if (pid != -2) { fprintf(stderr,"Argument out of context: %s (You've already specified the PID)\n", argv[i]); exit(11);}
			if (strcmp(argv[i],"all") == 0) { pid = -1; }
			else
			{
			   rc = sscanf (argv[i], "%d", &pid);
			   if (rc != 1) { fprintf(stderr,"Argument out of context: %s\n", argv[i]); exit(10);}
			}
			
		}
#if 0
	   else {
		// A switch. I don't like optarg, so I do it the hard way
		   switch (argv[i][1])
			{
				case 'f': // FILTER
				break;
				default:
				 fprintf(stderr,"Unknown switch: %s\n", argv[i]); exit(12);
			}
		}
#endif
	}

    loadTraceCodes(NULL); // Load default trace codes

    g_my_pid = getpid();
    g_filtered_pid = -1;

    kdebugRemove();
    kdebugBufs(0);
    kdebugInit();

    if (pid > -1)  {
		printf("Filtering PID: %d\n", pid);
		filterPID(pid, PID_INCLUDE);
			g_filtered_pid = pid;
		 }

     else { printf("Filtering myself (%d) out\n", g_my_pid);
    filterPID(getpid(),PID_EXCLUDE);
	}
    signal(2, handler);
    signal(15, handler);
    
    
    if (kdebugEnable(1)) { cleanup(); exit(1); };

    if ( !codes[0].code) { 
	fprintf(stderr,"Warning: No trace codes loaded - Continuing to log silently to output, without human readable event parsing\n");
	
	}
    readThreadMap();

    unsigned long bufSize = BUFCHUNK * NUMCHUNKS;
    unsigned char *buf = (unsigned char *) malloc(bufSize);
    memset(buf,'\0', bufSize);
    

    pthread_t tid;

#ifdef WANT_MULTITHREAD
    // Was thinking of making this multithreaded at one point, but figured single thread is just fine
    int rc = pthread_create (&tid,  NULL, reader, buf);
    pthread_join(&tid,  NULL);
#else
    reader(buf);
#endif

    return (0);

} // end main
