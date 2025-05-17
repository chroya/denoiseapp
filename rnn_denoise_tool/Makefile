CC=gcc
CFLAGS=-Wall -O3 -I./src
LDFLAGS=-lm

TARGET = rnn_denoise
SRC_DIR = src
SRCS = $(SRC_DIR)/main.c \
       $(SRC_DIR)/rnnoise.c \
       $(SRC_DIR)/rnn.c \
       $(SRC_DIR)/rnn_data.c \
       $(SRC_DIR)/pitch.c \
       $(SRC_DIR)/kiss_fft.c \
       $(SRC_DIR)/celt_lpc.c

OBJS = $(SRCS:.c=.o)

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJS) $(TARGET)

.PHONY: all clean 