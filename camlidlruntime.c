/* Helper functions for stub code generated by camlidl */

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/fail.h>
#include "camlidlruntime.h"

value camlidl_find_enum(int n, int *flags, int nflags, char *errmsg)
{
  int i;

  for (i = 0; i < nflags; i++) {
    if (n == flags[i]) return Val_int(i);
  }
  invalid_argument(errmsg);
}

value camlidl_alloc_flag_list(int n, int *flags, int nflags)
{
  value l = Val_int(0);
  int i;

  Begin_root(l)
    for (i = nflags - 1; i >= 0; i--)
      if (n & flags[i]) {
        value v = alloc_small(2, 0);
        Field(v, 0) = Val_int(i);
        Field(v, 1) = l;
        l = v;
        n &= ~ flags[i];
      }
  End_roots();
  return l;
}

mlsize_t camlidl_ptrarray_size(void ** array)
{
  mlsize_t i;

  for (i = 0; array[i] != NULL; i++) /*nothing*/;
  return i;
}

union alloc_block {
  union alloc_block * next;
  double force_align;
};

static union alloc_block * temp_blocks_head = NULL;

void * camlidl_temp_alloc(size_t size)
{
  union alloc_block * res = stat_alloc(sizeof(union alloc_block) + size);
  res->next = temp_blocks_head;
  temp_blocks_head = res;
  return (void *) (res + 1);
}

void camlidl_temp_free(void)
{
  union alloc_block * l;
  for (l = temp_blocks_head; l != NULL; l = l->next)
    stat_free((void *)(l + 1));
  temp_blocks_head = NULL;
}